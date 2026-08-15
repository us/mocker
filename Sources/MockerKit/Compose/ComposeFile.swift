import Foundation
import Yams
import CryptoKit

/// Represents a parsed docker-compose.yml file.
public struct ComposeFile: Sendable {
    public var services: [String: ComposeService]
    public var networks: [String: ComposeNetwork]
    public var volumes: [String: ComposeVolume]
    /// Top-level `name:` key — one of the project-name sources (see `resolveProjectName`).
    public var name: String?

    public init(
        services: [String: ComposeService] = [:],
        networks: [String: ComposeNetwork] = [:],
        volumes: [String: ComposeVolume] = [:],
        name: String? = nil
    ) {
        self.services = services
        self.networks = networks
        self.volumes = volumes
        self.name = name
    }

    /// Default compose file names searched in order, matching Docker Compose V2 behaviour.
    public static let defaultFileNames = ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"]

    /// Resolve the Docker Compose project directory: explicit flag → dir of first non-'-' '-f' entry → cwd.
    public static func resolveProjectDirectory(explicit: String?, files: [String], cwd: String) -> URL {
        let cwdURL = URL(fileURLWithPath: cwd, isDirectory: true)
        if let explicit, !explicit.isEmpty {
            return URL(fileURLWithPath: explicit, relativeTo: cwdURL).standardizedFileURL
        }
        if let firstReal = files.first(where: { $0 != "-" }) {
            return URL(fileURLWithPath: firstReal, relativeTo: cwdURL).standardizedFileURL.deletingLastPathComponent()
        }
        return cwdURL
    }

    /// Normalize a string to a valid compose project name: lowercase, only
    /// `[a-z0-9_-]`, and starting with an alphanumeric — the character set Docker
    /// Compose enforces. Anything else becomes a dash.
    public static func normalizeProjectName(_ s: String) -> String {
        var chars = s.lowercased().map { ch -> Character in
            ch.isASCII && (ch.isLetter || ch.isNumber || ch == "_" || ch == "-") ? ch : "-"
        }
        while let first = chars.first, !(first.isLetter || first.isNumber) {
            chars.removeFirst()
        }
        // A name of only invalid characters leaves nothing to work with; keep the
        // previous placeholder rather than emitting resource names starting with `-`.
        return chars.isEmpty ? "default" : String(chars)
    }

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

    /// Parse a compose file at 'path'. '.env' auto-discovery uses 'projectDir/.env'.
    /// Top-level `include:` entries are resolved relative to the file's own directory.
    /// - Parameter variables: values the caller resolved before parsing, exposed to
    ///   `${VAR}` interpolation. Compose uses this for `COMPOSE_PROJECT_NAME`.
    public static func load(
        from path: String,
        projectDir: URL,
        variables: [String: String] = [:]
    ) throws -> ComposeFile {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw MockerError.composeFileNotFound(path)
        }

        let content = try String(contentsOf: url, encoding: .utf8)
        return try parseFile(
            content: content,
            fileDir: url.standardizedFileURL.deletingLastPathComponent(),
            envFiles: [projectDir.appendingPathComponent(".env").path],
            variables: variables,
            visited: [url.resolvingSymlinksInPath().path],
            depth: 0
        )
    }

    /// Parse a compose file from an in-memory string (stdin `-f -`).
    /// '.env' auto-discovery uses 'projectDir/.env'. Throws if content is empty.
    /// `include:` paths resolve relative to `projectDir`, which is all the location
    /// context a piped file has.
    public static func load(
        content: String,
        projectDir: URL,
        variables: [String: String] = [:]
    ) throws -> ComposeFile {
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MockerError.composeParseError("compose file content is empty")
        }
        return try parseFile(
            content: content,
            fileDir: projectDir,
            envFiles: [projectDir.appendingPathComponent(".env").path],
            variables: variables,
            visited: [],
            depth: 0
        )
    }

    /// Maximum `include:` nesting depth — a cheap backstop next to the cycle guard.
    private static let maxIncludeDepth = 10

    /// Parse one compose file and recursively resolve its `include:` entries.
    ///
    /// - `fileDir`: directory of the file being parsed; `include` paths resolve against it.
    /// - `envFiles`: env files driving `${VAR}` interpolation for *this* file only —
    ///   an include's env never leaks into its parent or siblings.
    /// - `visited`: canonical paths on the current include chain, for cycle detection.
    private static func parseFile(
        content: String,
        fileDir: URL,
        envFiles: [String],
        variables: [String: String] = [:],
        visited: Set<String>,
        depth: Int
    ) throws -> ComposeFile {
        guard depth <= maxIncludeDepth else {
            throw MockerError.composeParseError("include: nesting deeper than \(maxIncludeDepth) levels")
        }

        var dotEnv: [String: String] = [:]
        for file in envFiles {
            dotEnv.merge(loadDotEnv(from: file)) { _, new in new }
        }


        // Substitute ${VAR:-default} and $VAR patterns before YAML parsing
        let substituted = substituteVariables(in: content, dotEnv: dotEnv, resolved: variables)
        guard let dict = try Yams.load(yaml: substituted) as? [String: Any] else {
            throw MockerError.composeParseError("Invalid YAML structure")
        }
        let own = try parse(dict)

        guard let includes = try parseIncludes(dict["include"]), !includes.isEmpty else {
            return own
        }

        var included: [ComposeFile] = []
        for entry in includes {
            for rawPath in entry.paths {
                let url = URL(fileURLWithPath: rawPath, relativeTo: fileDir).standardizedFileURL
                let canonical = url.resolvingSymlinksInPath().path
                guard !visited.contains(canonical) else {
                    throw MockerError.composeParseError("include: cycle detected at \(url.path)")
                }
                guard let body = try? String(contentsOf: url, encoding: .utf8) else {
                    throw MockerError.composeFileNotFound(url.path)
                }

                // Per the spec, an entry's project_directory defaults to the included
                // file's own directory, and its env_file to `.env` beneath that.
                let entryDir = entry.projectDirectory
                    .map { URL(fileURLWithPath: $0, relativeTo: fileDir).standardizedFileURL }
                    ?? url.deletingLastPathComponent()
                let entryEnvFiles = entry.envFiles.isEmpty
                    ? [entryDir.appendingPathComponent(".env").path]
                    : entry.envFiles.map { URL(fileURLWithPath: $0, relativeTo: entryDir).path }

                var model = try parseFile(
                    content: body,
                    fileDir: url.deletingLastPathComponent(),
                    envFiles: entryEnvFiles,
                    variables: variables,
                    visited: visited.union([canonical]),
                    depth: depth + 1
                )
                // The orchestrator only knows the top-level project directory, so an
                // included service's relative paths are anchored to the include's own
                // directory here instead.
                model.anchorRelativePaths(to: entryDir)
                // An include contributes resources, not identity: its `name:` must not
                // become the including project's name.
                model.name = nil
                included.append(model)
            }
        }

        // Parent last: its own inline definitions override anything it includes.
        return merge(included + [own])
    }

    /// One `include:` entry, in either the short (`- path/to/file.yml`) or long
    /// (`- {path, project_directory, env_file}`) form.
    private struct IncludeEntry {
        var paths: [String]
        var projectDirectory: String?
        var envFiles: [String]
    }

    /// Decode the top-level `include:` list. Returns nil when the key is absent.
    /// A malformed entry is an error: silently dropping it is the very failure this
    /// element was added to fix.
    private static func parseIncludes(_ value: Any?) throws -> [IncludeEntry]? {
        guard let value else { return nil }
        guard let list = value as? [Any] else {
            throw MockerError.composeParseError("include: must be a list of entries")
        }
        return try list.map { item in
            if let path = item as? String {
                return IncludeEntry(paths: [path], projectDirectory: nil, envFiles: [])
            }
            guard let dict = item as? [String: Any] else {
                throw MockerError.composeParseError("include: entry must be a path or a mapping")
            }
            let paths: [String]
            if let path = dict["path"] as? String {
                paths = [path]
            } else if let list = dict["path"] as? [Any] {
                paths = list.map { "\($0)" }
            } else {
                throw MockerError.composeParseError("include: entry is missing a `path`")
            }
            guard !paths.isEmpty else {
                throw MockerError.composeParseError("include: entry has an empty `path`")
            }
            let envFiles: [String]
            if let file = dict["env_file"] as? String {
                envFiles = [file]
            } else if let list = dict["env_file"] as? [Any] {
                // Entries are either a path or the long form `{path, required}`.
                envFiles = try list.map { item in
                    if let path = item as? String { return path }
                    guard let path = (item as? [String: Any])?["path"] as? String else {
                        throw MockerError.composeParseError("include: env_file entry is missing a `path`")
                    }
                    return path
                }
            } else {
                envFiles = []
            }
            return IncludeEntry(
                paths: paths,
                projectDirectory: dict["project_directory"] as? String,
                envFiles: envFiles
            )
        }
    }

    /// Rewrite every service's relative bind-mount sources and build context to
    /// absolute paths under `dir`. Named volumes, anonymous volumes and
    /// already-absolute paths are left untouched.
    mutating func anchorRelativePaths(to dir: URL) {
        for (name, service) in services {
            services[name]?.volumes = service.volumes.map { Self.anchorVolumeSpec($0, to: dir) }
            // `build.dockerfile` needs no anchoring of its own: it is resolved against
            // the build context, which is absolute once this runs.
            guard var build = service.build, !build.context.hasPrefix("/") else { continue }
            build.context = dir.appendingPathComponent(build.context).standardized.path
            services[name]?.build = build
        }
    }

    /// Absolutize the source of a `source:target[:mode]` spec when it is a relative
    /// bind mount. Mirrors the branch conditions in `ComposeOrchestrator.resolveVolumeMounts`.
    static func anchorVolumeSpec(_ spec: String, to dir: URL) -> String {
        let parts = spec.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return spec }  // anonymous volume: "/data"
        let source = String(parts[0])
        guard !source.isEmpty, !source.hasPrefix("/"), !source.hasPrefix("~"),
              source.hasPrefix(".") || source.contains("/") else {
            return spec  // absolute, home-relative, or a named volume
        }
        return dir.appendingPathComponent(source).standardized.path + ":" + String(parts[1])
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
    /// - Parameter resolved: values the caller worked out itself (the project name), which
    ///   outrank both `.env` and the environment because they are the effective values.
    private static func substituteVariables(
        in yaml: String,
        dotEnv: [String: String],
        resolved: [String: String] = [:]
    ) -> String {
        let processEnv = ProcessInfo.processInfo.environment
        // .env is the weakest, then the shell, then whatever the caller resolved.
        let env = dotEnv
            .merging(processEnv) { _, new in new }
            .merging(resolved) { _, new in new }

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

    /// Parse a docker-compose.yml string. `include:` is not resolved here — it needs
    /// the file's location, so it is handled by `load(from:projectDir:)`.
    public static func parse(_ yaml: String) throws -> ComposeFile {
        guard let dict = try Yams.load(yaml: yaml) as? [String: Any] else {
            throw MockerError.composeParseError("Invalid YAML structure")
        }
        return try parse(dict)
    }

    private static func parse(_ dict: [String: Any]) throws -> ComposeFile {
        let services = try parseServices(dict["services"] as? [String: Any] ?? [:])
        let networks = parseNetworks(dict["networks"] as? [String: Any] ?? [:])
        let volumes = parseVolumes(dict["volumes"] as? [String: Any] ?? [:])

        return ComposeFile(
            services: services, networks: networks, volumes: volumes,
            name: dict["name"] as? String
        )
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
            // `external` is either a bool or, in the legacy long form, a mapping
            // (`external: {name: shared}`) — both mean "not owned by this project".
            let externalDict = netDict["external"] as? [String: Any]
            let external = netDict["external"] as? Bool ?? (netDict["external"] != nil)
            networks[name] = ComposeNetwork(
                name: name,
                driver: netDict["driver"] as? String ?? "bridge",
                external: external,
                customName: netDict["name"] as? String ?? externalDict?["name"] as? String
            )
        }
        return networks
    }

    private static func parseVolumes(_ dict: [String: Any]) -> [String: ComposeVolume] {
        var volumes: [String: ComposeVolume] = [:]
        for (name, value) in dict {
            let volDict = value as? [String: Any] ?? [:]
            // `external` is either a bool or, in the legacy long form, a mapping
            // (`external: {name: shared}`) — both mean "not owned by this project".
            let externalDict = volDict["external"] as? [String: Any]
            let external = volDict["external"] as? Bool ?? (volDict["external"] != nil)
            volumes[name] = ComposeVolume(
                name: name,
                driver: volDict["driver"] as? String ?? "local",
                external: external,
                customName: volDict["name"] as? String ?? externalDict?["name"] as? String
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
        return ComposeFile(services: filteredServices, networks: networks, volumes: volumes, name: self.name)
    }

    /// Throw when a service joins a network the file never declares — the container
    /// would otherwise be started against a network nothing creates.
    public func validateNetworkReferences() throws {
        for service in services.values.sorted(by: { $0.name < $1.name }) {
            for network in service.networks where networks[network] == nil {
                throw MockerError.composeParseError(
                    "service \(service.name) refers to undefined network \(network)")
            }
        }
    }

    /// Throw `no such service: <name>` for any requested name absent from the project,
    /// matching `docker compose`'s behaviour of erroring instead of silently doing nothing.
    /// Only literal, user-typed names are checked — transitive dependencies are resolved
    /// afterwards by `filtering(services:)`.
    public func validateServiceNames(_ requested: [String]) throws {
        for name in requested where services[name] == nil {
            throw MockerError.operationFailed("no such service: \(name)")
        }
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
            result.name = overlay.name ?? result.name
        }
        return result
    }

    /// Resolve the effective Compose project name, matching upstream precedence:
    /// `-p` flag → `COMPOSE_PROJECT_NAME` in the environment → `COMPOSE_PROJECT_NAME`
    /// in `projectDir/.env` → top-level `name:` in the compose file → directory basename.
    public static func resolveProjectName(
        explicit: String?,
        composeFileName: String? = nil,
        projectDir: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let candidates = [
            explicit,
            environment["COMPOSE_PROJECT_NAME"],
            loadDotEnv(from: projectDir.appendingPathComponent(".env").path)["COMPOSE_PROJECT_NAME"],
            composeFileName,
            projectDir.lastPathComponent,
        ]
        let resolved = candidates.compactMap { $0 }.first { !$0.isEmpty } ?? projectDir.lastPathComponent
        return normalizeProjectName(resolved)
    }
}

/// A service definition in a compose file.
public struct ComposeService: Sendable {
    public var name: String
    public var image: String?
    public var build: ComposeBuild?
    public var command: [String]
    public var entrypoint: [String] = []
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

    // deploy.restart_policy — Docker Compose deploy spec
    public var restartPolicyDelay: String?
    public var restartPolicyMaxAttempts: Int?
    public var restartPolicyWindow: String?

    private enum HashCodingKeys: String, CodingKey {
        case name, image, command, entrypoint, environment, ports, volumes, networks
        case restart, labels, hostname, workingDir
        case memLimit, cpus, memReservation, cpusReservation, memSwapLimit
        case shmSize, pidsLimit
        case restartPolicyDelay, restartPolicyMaxAttempts, restartPolicyWindow
    }

    /// Compute a stable `sha256:<hex>` hash of the normalized service config.
    ///
    /// `sortedKeys` is mandatory: without it, two services with identical content but
    /// different source-field order would hash differently. Mirrors Docker's
    /// `ServiceHash` algorithm at `pkg/compose/hash.go:27-43`.
    public static func hash(of service: ComposeService) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(service)) ?? Data()
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:" + hex
    }

    public static func parse(name: String, from dict: [String: Any]) throws -> ComposeService {
        let environment = parseEnvironment(dict["environment"])
        let ports = (dict["ports"] as? [Any])?.compactMap { "\($0)" } ?? []
        let volumes = (dict["volumes"] as? [Any])?.compactMap { "\($0)" } ?? []
        // Both spellings are valid: a list of names, or a mapping whose keys are the
        // names and whose values carry per-network options such as `aliases`.
        let networks: [String]
        if let list = dict["networks"] as? [Any] {
            networks = list.compactMap { "\($0)" }
        } else if let mapping = dict["networks"] as? [String: Any] {
            networks = mapping.keys.sorted()
        } else {
            networks = []
        }
        let dependsOn = parseDependsOn(dict["depends_on"])
        let command = parseCommand(dict["command"])
        let entrypoint = parseCommand(dict["entrypoint"])
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
        let memLimit = parseStringValue(deployLeaf(dict["deploy"], "resources", "limits", "memory")) ?? parseStringValue(dict["mem_limit"])
        let cpus = parseStringValue(deployLeaf(dict["deploy"], "resources", "limits", "cpus")) ?? parseStringValue(dict["cpus"])
        let memReservation = parseStringValue(deployLeaf(dict["deploy"], "resources", "reservations", "memory")) ?? parseStringValue(dict["mem_reservation"])
        let cpusReservation = parseStringValue(deployLeaf(dict["deploy"], "resources", "reservations", "cpus"))
        let memSwapLimit = parseStringValue(dict["memswap_limit"])
        let shmSize = parseStringValue(dict["shm_size"])
        let pidsLimit = parseIntValue(deployLeaf(dict["deploy"], "resources", "limits", "pids")) ?? parseIntValue(dict["pids_limit"])

        // Parse deploy.restart_policy — overrides legacy `restart` field per Compose spec
        let restartPolicy = parseRestartPolicy(dict["deploy"])
        let restartValue: String?
        let restartPolicyDelay: String?
        let restartPolicyMaxAttempts: Int?
        let restartPolicyWindow: String?
        if let rp = restartPolicy {
            // A restart_policy without a `condition` still honors the legacy `restart` field.
            restartValue = rp.condition.map { mapRestartCondition($0) } ?? (dict["restart"] as? String)
            restartPolicyDelay = rp.delay
            restartPolicyMaxAttempts = rp.maxAttempts
            restartPolicyWindow = rp.window
        } else {
            restartValue = dict["restart"] as? String
            restartPolicyDelay = nil
            restartPolicyMaxAttempts = nil
            restartPolicyWindow = nil
        }

        return ComposeService(
            name: name,
            image: dict["image"] as? String,
            build: build,
            command: command,
            entrypoint: entrypoint,
            environment: environment,
            ports: ports,
            volumes: volumes,
            networks: networks,
            dependsOn: dependsOn,
            restart: restartValue,
            labels: labels,
            hostname: dict["hostname"] as? String,
            workingDir: dict["working_dir"] as? String,
            memLimit: memLimit,
            cpus: cpus,
            memReservation: memReservation,
            cpusReservation: cpusReservation,
            memSwapLimit: memSwapLimit,
            shmSize: shmSize,
            pidsLimit: pidsLimit,
            restartPolicyDelay: restartPolicyDelay,
            restartPolicyMaxAttempts: restartPolicyMaxAttempts,
            restartPolicyWindow: restartPolicyWindow
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
            entrypoint: other.entrypoint.isEmpty ? entrypoint : other.entrypoint,
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
            pidsLimit: other.pidsLimit ?? pidsLimit,
            restartPolicyDelay: other.restartPolicyDelay ?? restartPolicyDelay,
            restartPolicyMaxAttempts: other.restartPolicyMaxAttempts ?? restartPolicyMaxAttempts,
            restartPolicyWindow: other.restartPolicyWindow ?? restartPolicyWindow
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

    /// Walk a nested deploy path like `deploy.resources.limits.memory` and return the raw leaf node.
    /// Callers apply `parseStringValue`/`parseIntValue` to coerce it to the type they need.
    private static func deployLeaf(_ value: Any?, _ path: String...) -> Any? {
        guard let dict = value as? [String: Any] else { return nil }
        var current: Any? = dict
        for key in path {
            guard let d = current as? [String: Any] else { return nil }
            current = d[key]
        }
        return current
    }

    // MARK: - Restart policy parsing

    /// Parse `deploy.restart_policy` section.
    private static func parseRestartPolicy(_ deployValue: Any?) -> RestartPolicyConfig? {
        guard let deploy = deployValue as? [String: Any],
              let rp = deploy["restart_policy"] as? [String: Any] else { return nil }
        return RestartPolicyConfig(
            condition: rp["condition"] as? String,
            delay: rp["delay"] as? String,
            maxAttempts: rp["max_attempts"] as? Int,
            window: rp["window"] as? String
        )
    }

    /// Map Docker Compose restart_policy.condition to Docker/mocker restart values.
    /// - `none` → `no`
    /// - `any` → `always`
    /// - `on-failure` → `on-failure`
    private static func mapRestartCondition(_ condition: String) -> String {
        switch condition {
        case "none": return "no"
        case "any": return "always"
        default: return condition
        }
    }
}

/// Parsed `deploy.restart_policy` section from a compose file.
struct RestartPolicyConfig: Sendable {
    var condition: String?
    var delay: String?
    var maxAttempts: Int?
    var window: String?
}

extension ComposeService: Encodable {
    /// Emits only the hash-relevant fields per `HashCodingKeys`, excluding
    /// Docker-normalized fields (`Build`, `DependsOn`, etc.). Used by
    /// `hash(of:)`; not intended as a general-purpose service serializer.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: HashCodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(image, forKey: .image)
        try c.encode(command, forKey: .command)
        try c.encode(entrypoint, forKey: .entrypoint)
        try c.encode(environment, forKey: .environment)
        try c.encode(ports, forKey: .ports)
        try c.encode(volumes, forKey: .volumes)
        try c.encode(networks, forKey: .networks)
        try c.encodeIfPresent(restart, forKey: .restart)
        try c.encode(labels, forKey: .labels)
        try c.encodeIfPresent(hostname, forKey: .hostname)
        try c.encodeIfPresent(workingDir, forKey: .workingDir)
        try c.encodeIfPresent(memLimit, forKey: .memLimit)
        try c.encodeIfPresent(cpus, forKey: .cpus)
        try c.encodeIfPresent(memReservation, forKey: .memReservation)
        try c.encodeIfPresent(cpusReservation, forKey: .cpusReservation)
        try c.encodeIfPresent(memSwapLimit, forKey: .memSwapLimit)
        try c.encodeIfPresent(shmSize, forKey: .shmSize)
        try c.encodeIfPresent(pidsLimit, forKey: .pidsLimit)
        try c.encodeIfPresent(restartPolicyDelay, forKey: .restartPolicyDelay)
        try c.encodeIfPresent(restartPolicyMaxAttempts, forKey: .restartPolicyMaxAttempts)
        try c.encodeIfPresent(restartPolicyWindow, forKey: .restartPolicyWindow)
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
    /// The key this network is declared under in the compose file.
    public var name: String
    public var driver: String
    /// `external: true` — the network lives outside the project lifecycle: it is
    /// neither created nor removed by the project, only joined.
    public var external: Bool
    /// Explicit `name:` override — used verbatim, without the project prefix.
    public var customName: String?

    public init(name: String, driver: String = "bridge", external: Bool = false, customName: String? = nil) {
        self.name = name
        self.driver = driver
        self.external = external
        self.customName = customName
    }

    /// The network's real name in the runtime: an explicit `name:` wins, an external
    /// network keeps its declared key, and everything else is project-namespaced.
    public func runtimeName(projectName: String) -> String {
        if let customName { return customName }
        return external ? name : "\(projectName)-\(name)"
    }
}

/// Volume definition in a compose file.
public struct ComposeVolume: Sendable {
    /// The key this volume is declared under in the compose file.
    public var name: String
    public var driver: String
    /// `external: true` — the volume lives outside the project lifecycle: it is
    /// neither created by `up` nor removed by `down --volumes`.
    public var external: Bool
    /// Explicit `name:` override — used verbatim, without the project prefix.
    public var customName: String?

    public init(name: String, driver: String = "local", external: Bool = false, customName: String? = nil) {
        self.name = name
        self.driver = driver
        self.external = external
        self.customName = customName
    }

    /// The volume's real name in the runtime: an explicit `name:` wins, an external
    /// volume keeps its declared key, and everything else is project-namespaced.
    public func runtimeName(projectName: String) -> String {
        if let customName { return customName }
        return external ? name : "\(projectName)-\(name)"
    }
}
