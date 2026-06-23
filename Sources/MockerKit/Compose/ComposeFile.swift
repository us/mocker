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

    /// Default compose file names searched in order, matching Docker Compose V2 behaviour.
    public static let defaultFileNames = ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"]

    /// Return the path of the first default compose file found in `directory`.
    public static func findDefault(in directory: String = FileManager.default.currentDirectoryPath) -> String? {
        for name in defaultFileNames {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
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

    /// Merge multiple compose files in order, matching `docker compose -f a -f b`
    /// overlay semantics: later files override earlier ones. A new service is
    /// inserted; an existing service is field-merged (see `ComposeService.merged`).
    /// Networks and volumes are unioned with later definitions winning on key
    /// collision. A single-file input is returned unchanged.
    public static func merge(_ files: [ComposeFile]) -> ComposeFile {
        guard var result = files.first else { return ComposeFile() }
        for overlay in files.dropFirst() {
            for (name, service) in overlay.services {
                if let base = result.services[name] {
                    result.services[name] = base.merged(with: service)
                } else {
                    result.services[name] = service
                }
            }
            result.networks.merge(overlay.networks) { _, new in new }
            result.volumes.merge(overlay.volumes) { _, new in new }
        }
        return result
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

    // Resource limits — Docker Compose spec (legacy top-level + deploy.resources)
    public var memLimit: String?
    public var cpus: String?
    public var memReservation: String?
    public var cpusReservation: String?
    public var memSwapLimit: String?
    public var shmSize: String?
    public var pidsLimit: Int?

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
                    dockerfile: buildDict["dockerfile"] as? String,
                    target: buildDict["target"] as? String,
                    args: parseBuildArgs(buildDict["args"])
                )
            }
        }

        // Parse resource limits: deploy.resources overrides legacy top-level fields
        let memLimit = parseDeployNested(dict["deploy"], "resources", "limits", "memory") ?? parseStringValue(dict["mem_limit"])
        let cpus = parseDeployNested(dict["deploy"], "resources", "limits", "cpus") ?? parseCpusValue(dict["cpus"])
        let memReservation = parseDeployNested(dict["deploy"], "resources", "reservations", "memory") ?? parseStringValue(dict["mem_reservation"])
        let cpusReservation = parseDeployNested(dict["deploy"], "resources", "reservations", "cpus")
        let memSwapLimit = parseStringValue(dict["memswap_limit"])
        let shmSize = parseStringValue(dict["shm_size"])
        let pidsLimit = parseIntValue(dict["pids_limit"]) ?? parseDeployInt(dict["deploy"], "resources", "limits", "pids")

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
            workingDir: dict["working_dir"] as? String,
            memLimit: memLimit,
            cpus: cpus,
            memReservation: memReservation,
            cpusReservation: cpusReservation,
            memSwapLimit: memSwapLimit,
            shmSize: shmSize,
            pidsLimit: pidsLimit
        )
    }

    /// Default tag for an image built from this service's `build` config.
    public func buildTag(projectName: String) -> String {
        image ?? "\(projectName)-\(name):latest"
    }

    /// Overlay `other` onto `self` (other wins) for `docker compose` multi-file
    /// merge. Scalars take the later value when present; `environment` and
    /// `labels` are field-merged (later wins on key collision); list-valued
    /// fields are replaced by the later file unless it is empty.
    func merged(with other: ComposeService) -> ComposeService {
        ComposeService(
            name: name,
            image: other.image ?? image,
            build: other.build ?? build,
            command: other.command.isEmpty ? command : other.command,
            environment: environment.merging(other.environment) { _, new in new },
            ports: other.ports.isEmpty ? ports : other.ports,
            volumes: other.volumes.isEmpty ? volumes : other.volumes,
            networks: other.networks.isEmpty ? networks : other.networks,
            dependsOn: other.dependsOn.isEmpty ? dependsOn : other.dependsOn,
            restart: other.restart ?? restart,
            labels: labels.merging(other.labels) { _, new in new },
            hostname: other.hostname ?? hostname,
            workingDir: other.workingDir ?? workingDir,
            memLimit: other.memLimit ?? memLimit,
            cpus: other.cpus ?? cpus,
            memReservation: other.memReservation ?? memReservation,
            cpusReservation: other.cpusReservation ?? cpusReservation,
            memSwapLimit: other.memSwapLimit ?? memSwapLimit,
            shmSize: other.shmSize ?? shmSize,
            pidsLimit: other.pidsLimit ?? pidsLimit
        )
    }

    /// Decide how this service's image should be obtained, per the Compose spec.
    ///
    /// When `build:` is present (and not disabled via `--no-build`) the image is
    /// built from the Dockerfile context and tagged with `image:` if specified —
    /// it is never pulled. Only when there is no buildable config does `image:`
    /// trigger a registry pull. This is a pure function so it can be unit-tested
    /// without the container runtime.
    public func resolveImageSource(projectName: String, noBuild: Bool = false) -> ComposeImageSource {
        if let build, !noBuild {
            return .build(tag: buildTag(projectName: projectName), build: build)
        } else if let image {
            return .pull(image: image)
        } else {
            return .none
        }
    }

    /// Whether an existing image matches `tag` (repository suffix + tag), used to
    /// skip rebuilds when `--build` was not requested.
    public static func imageMatches(_ info: ImageInfo, tag: String) -> Bool {
        guard let ref = try? ImageReference.parse(tag) else { return false }
        return info.repository.hasSuffix(ref.repository) && info.tag == ref.tag
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

    /// Parse `build.args`, accepting both the map form (`KEY: value`) and the
    /// list form (`- KEY=value`). A bare `KEY` (no `=`) inherits the value from
    /// the host environment, matching Docker Compose semantics. An explicit empty
    /// value (`KEY=`) is preserved as an empty string rather than dropped.
    static func parseBuildArgs(_ value: Any?) -> [String: String] {
        var args: [String: String] = [:]
        if let dict = value as? [String: Any] {
            for (k, v) in dict { args[k] = "\(v)" }
        } else if let list = value as? [Any] {
            for item in list {
                let str = "\(item)"
                if let eq = str.firstIndex(of: "=") {
                    let key = String(str[str.startIndex..<eq])
                    let val = String(str[str.index(after: eq)...])
                    args[key] = val
                } else {
                    args[str] = ProcessInfo.processInfo.environment[str] ?? ""
                }
            }
        }
        return args
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

    // MARK: - Resource limit parsing

    /// Extract a string value from a YAML node (string or number).
    private static func parseStringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let str = value as? String { return str }
        if let num = value as? Int { return String(num) }
        if let num = value as? Double { return String(num) }
        return nil
    }

    /// Extract an integer value from a YAML node.
    private static func parseIntValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let int = value as? Int { return int }
        if let str = value as? String, let int = Int(str) { return int }
        return nil
    }

    /// Parse `cpus` — fractional number (`0.5`) or string (`"0.50"`).
    private static func parseCpusValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let str = value as? String { return str }
        if let num = value as? Double { return String(num) }
        if let num = value as? Int { return String(num) }
        return nil
    }

    /// Walk a nested deploy path like `deploy.resources.limits.memory`.
    private static func parseDeployNested(_ value: Any?, _ path: String...) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        var current: Any? = dict
        for key in path {
            guard let d = current as? [String: Any] else { return nil }
            current = d[key]
        }
        return parseStringValue(current)
    }

    /// Walk a nested deploy path for integer values like `deploy.resources.limits.pids`.
    private static func parseDeployInt(_ value: Any?, _ path: String...) -> Int? {
        guard let dict = value as? [String: Any] else { return nil }
        var current: Any? = dict
        for key in path {
            guard let d = current as? [String: Any] else { return nil }
            current = d[key]
        }
        return parseIntValue(current)
    }
}

/// Build configuration for a compose service.
public struct ComposeBuild: Sendable, Equatable {
    public var context: String
    public var dockerfile: String?
    /// Target stage to build (maps to `container build --target <stage>`).
    public var target: String?
    /// Build-time ARG values declared under `build.args` in the compose file.
    public var args: [String: String]

    public init(
        context: String,
        dockerfile: String? = nil,
        target: String? = nil,
        args: [String: String] = [:]
    ) {
        self.context = context
        self.dockerfile = dockerfile
        self.target = target
        self.args = args
    }

    /// Build args formatted as `KEY=VALUE` strings for the `container build --build-arg` flag.
    public var argList: [String] {
        args.map { "\($0.key)=\($0.value)" }
    }
}

/// How a service's image should be obtained during `compose up`.
public enum ComposeImageSource: Sendable, Equatable {
    /// Pull `image` from a registry.
    case pull(image: String)
    /// Build from the Dockerfile context and tag the result with `tag`.
    case build(tag: String, build: ComposeBuild)
    /// Nothing to do (no image and no build config).
    case none
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
