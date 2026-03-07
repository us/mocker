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

        let content = try String(contentsOf: url, encoding: .utf8)
        return try parse(content)
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
