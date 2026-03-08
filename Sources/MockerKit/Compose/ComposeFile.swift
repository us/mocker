import Foundation
import Yams

/// Represents a parsed docker-compose.yml file.
public struct ComposeFile: Sendable {
    public var services: [String: ComposeService]
    public var networks: [String: ComposeNetwork]
    public var volumes: [String: ComposeVolume]

    public init(
        services: [String: ComposeService] = [:],
        networks: [String: ComposeNetwork] = [:],
        volumes: [String: ComposeVolume] = [:]
    ) {
        self.services = services
        self.networks = networks
        self.volumes = volumes
    }

    /// Parse a docker-compose.yml file from a path.
    public static func load(from path: String) throws -> ComposeFile {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw MockerError.composeFileNotFound(path)
        }

        var content = try String(contentsOf: url, encoding: .utf8)

        // Load .env file from same directory for variable substitution
        let envFile = url.deletingLastPathComponent().appendingPathComponent(".env").path
        let dotEnv = loadDotEnv(from: envFile)

        // Substitute ${VAR:-default} and $VAR patterns before YAML parsing
        content = substituteVariables(in: content, dotEnv: dotEnv)

        return try parse(content)
    }

    /// Load key=value pairs from a .env file.
    private static func loadDotEnv(from path: String) -> [String: String] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var env: [String: String] = [:]
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            env[key] = value
        }
        return env
    }

    /// Substitute ${VAR}, ${VAR:-default}, and $VAR patterns using env + dotEnv.
    private static func substituteVariables(in yaml: String, dotEnv: [String: String]) -> String {
        let processEnv = ProcessInfo.processInfo.environment
        // dotEnv takes lower priority than actual environment
        let env = dotEnv.merging(processEnv) { _, new in new }

        var result = yaml
        // Match ${VAR:-default}, ${VAR-default}, ${VAR}
        let pattern = #"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::?-([^}]*))?\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }

        // Process from end to start to preserve offsets
        let ns = result as NSString
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let varName = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                ? ns.substring(with: match.range(at: 1)) : ""
            let defaultVal = match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound
                ? ns.substring(with: match.range(at: 2)) : nil

            let resolved = env[varName] ?? defaultVal ?? ""
            result.replaceSubrange(range, with: resolved)
        }
        return result
    }

    /// Parse a docker-compose.yml string.
    public static func parse(_ yaml: String) throws -> ComposeFile {
        guard let dict = try Yams.load(yaml: yaml) as? [String: Any] else {
            throw MockerError.composeParseError("Invalid YAML structure")
        }

        let services = try parseServices(dict["services"] as? [String: Any] ?? [:])
        let networks = parseNetworks(dict["networks"] as? [String: Any] ?? [:])
        let volumes = parseVolumes(dict["volumes"] as? [String: Any] ?? [:])

        return ComposeFile(services: services, networks: networks, volumes: volumes)
    }

    private static func parseServices(_ dict: [String: Any]) throws -> [String: ComposeService] {
        var services: [String: ComposeService] = [:]
        for (name, value) in dict {
            guard let serviceDict = value as? [String: Any] else { continue }
            services[name] = try ComposeService.parse(name: name, from: serviceDict)
        }
        return services
    }

    private static func parseNetworks(_ dict: [String: Any]) -> [String: ComposeNetwork] {
        var networks: [String: ComposeNetwork] = [:]
        for (name, value) in dict {
            let netDict = value as? [String: Any] ?? [:]
            networks[name] = ComposeNetwork(
                name: name,
                driver: netDict["driver"] as? String ?? "bridge"
            )
        }
        return networks
    }

    private static func parseVolumes(_ dict: [String: Any]) -> [String: ComposeVolume] {
        var volumes: [String: ComposeVolume] = [:]
        for (name, value) in dict {
            let volDict = value as? [String: Any] ?? [:]
            volumes[name] = ComposeVolume(
                name: name,
                driver: volDict["driver"] as? String ?? "local"
            )
        }
        return volumes
    }

    /// Get services in dependency order (topological sort).
    public func serviceOrder() -> [String] {
        var visited = Set<String>()
        var order: [String] = []

        func visit(_ name: String) {
            guard !visited.contains(name) else { return }
            visited.insert(name)
            if let service = services[name] {
                for dep in service.dependsOn {
                    visit(dep)
                }
            }
            order.append(name)
        }

        for name in services.keys.sorted() {
            visit(name)
        }
        return order
    }

    /// Return a new ComposeFile containing only the requested services
    /// and their transitive dependencies.
    public func filtering(services requested: [String]) -> ComposeFile {
        var included = Set<String>()

        func include(_ name: String) {
            guard !included.contains(name), let svc = services[name] else { return }
            included.insert(name)
            for dep in svc.dependsOn { include(dep) }
        }

        for name in requested { include(name) }

        let filteredServices = services.filter { included.contains($0.key) }
        return ComposeFile(services: filteredServices, networks: networks, volumes: volumes)
    }
}

/// A service definition in a compose file.
public struct ComposeService: Sendable {
    public var name: String
    public var image: String?
    public var build: ComposeBuild?
    public var command: [String]
    public var environment: [String: String]
    public var ports: [String]
    public var volumes: [String]
    public var networks: [String]
    public var dependsOn: [String]
    public var restart: String?
    public var labels: [String: String]
    public var hostname: String?
    public var workingDir: String?

    public static func parse(name: String, from dict: [String: Any]) throws -> ComposeService {
        let environment = parseEnvironment(dict["environment"])
        let ports = (dict["ports"] as? [Any])?.compactMap { "\($0)" } ?? []
        let volumes = (dict["volumes"] as? [Any])?.compactMap { "\($0)" } ?? []
        let networks = (dict["networks"] as? [Any])?.compactMap { "\($0)" } ?? []
        let dependsOn = parseDependsOn(dict["depends_on"])
        let command = parseCommand(dict["command"])
        let labels = (dict["labels"] as? [String: String]) ?? [:]

        var build: ComposeBuild?
        if let buildVal = dict["build"] {
            if let buildStr = buildVal as? String {
                build = ComposeBuild(context: buildStr)
            } else if let buildDict = buildVal as? [String: Any] {
                build = ComposeBuild(
                    context: buildDict["context"] as? String ?? ".",
                    dockerfile: buildDict["dockerfile"] as? String
                )
            }
        }

        return ComposeService(
            name: name,
            image: dict["image"] as? String,
            build: build,
            command: command,
            environment: environment,
            ports: ports,
            volumes: volumes,
            networks: networks,
            dependsOn: dependsOn,
            restart: dict["restart"] as? String,
            labels: labels,
            hostname: dict["hostname"] as? String,
            workingDir: dict["working_dir"] as? String
        )
    }

    private static func parseEnvironment(_ value: Any?) -> [String: String] {
        var env: [String: String] = [:]
        if let dict = value as? [String: Any] {
            for (k, v) in dict { env[k] = "\(v)" }
        } else if let list = value as? [String] {
            for item in list {
                let parts = item.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    env[String(parts[0])] = String(parts[1])
                }
            }
        }
        return env
    }

    private static func parseDependsOn(_ value: Any?) -> [String] {
        if let list = value as? [String] {
            return list
        }
        if let dict = value as? [String: Any] {
            return Array(dict.keys)
        }
        return []
    }

    private static func parseCommand(_ value: Any?) -> [String] {
        if let str = value as? String {
            return str.split(separator: " ").map(String.init)
        }
        if let list = value as? [String] {
            return list
        }
        return []
    }
}

/// Build configuration for a compose service.
public struct ComposeBuild: Sendable {
    public var context: String
    public var dockerfile: String?

    public init(context: String, dockerfile: String? = nil) {
        self.context = context
        self.dockerfile = dockerfile
    }
}

/// Network definition in a compose file.
public struct ComposeNetwork: Sendable {
    public var name: String
    public var driver: String

    public init(name: String, driver: String = "bridge") {
        self.name = name
        self.driver = driver
    }
}

/// Volume definition in a compose file.
public struct ComposeVolume: Sendable {
    public var name: String
    public var driver: String

    public init(name: String, driver: String = "local") {
        self.name = name
        self.driver = driver
    }
}
