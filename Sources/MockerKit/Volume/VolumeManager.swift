import Foundation

/// Manages named volumes, which come in two kinds because each container is its own VM:
///
/// - native: an ext4 image from the `container` runtime. The guest owns it, so images
///   whose entrypoint chowns the data directory (redis, postgres) run, but only one
///   running container can attach it.
/// - directory: `<volumesPath>/<name>/_data`, bind-mounted over virtiofs. Any number of
///   containers can share it, but the guest cannot change ownership. Compose uses it for
///   a volume several services mount, and every volume from earlier releases is one.
public actor VolumeManager {
    private let runner: ProcessRunning
    private let cli: String
    private let storagePath: String

    /// Label the runtime puts on volumes it creates for `-v /path` (no name).
    static let anonymousLabel = "com.apple.container.resource.anonymous"

    public init(
        config: MockerConfig = MockerConfig(),
        runner: ProcessRunning = RealProcessRunner(),
        cli: String = CLIResolver.resolve()
    ) throws {
        self.runner = runner
        self.cli = cli
        self.storagePath = config.volumesPath
    }

    /// Reject names that would escape the volumes directory (directory volume paths interpolate the
    /// name, and a compose file can supply it verbatim) or misparse inside a
    /// `-v source:destination` argument. Anything else stays removable, including volumes
    /// created before this check.
    static func validateName(_ name: String) throws {
        let valid = !name.isEmpty
            && !name.contains("/")
            && !name.contains(":")
            && name != "."
            && name != ".."
        guard valid else {
            throw MockerError.operationFailed("invalid volume name: \(name)")
        }
    }

    /// The runtime's own naming rule for new volumes, checked up front so a compose
    /// project fails before it creates anything rather than half-way through.
    static func validateNewName(_ name: String) throws {
        try validateName(name)
        guard name.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]*$", options: .regularExpression) != nil else {
            throw MockerError.operationFailed(
                "invalid volume name: \(name) (must start with a letter or digit and contain only letters, digits, '_', '.' or '-')")
        }
    }

    /// Backing directory of a directory volume, or `nil` when `name` has none. Keyed on
    /// `_data` alone: an unreadable `meta.json` must never hide a populated directory.
    nonisolated func directoryPath(_ name: String) throws -> String? {
        try Self.validateName(name)
        let path = "\(storagePath)/\(name)/_data"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// What compose puts on the left of `-v source:dest` for a named volume: the backing
    /// directory of a directory volume, otherwise the name, which the runtime mounts as
    /// a native volume.
    public nonisolated func composeSource(_ name: String) throws -> String {
        try directoryPath(name) ?? name
    }

    /// Create a new native volume.
    public func create(name: String, driver: String = "local", labels: [String: String] = [:]) async throws -> VolumeInfo {
        // A directory volume owns the name: a native twin would be listed and removed
        // alongside it while compose keeps mounting the directory.
        guard try directoryPath(name) == nil else {
            throw MockerError.operationFailed("volume \(name) already exists")
        }
        try Self.validateNewName(name)
        _ = driver // the runtime has a single local driver

        var arguments = ["volume", "create"]
        for (key, value) in labels.sorted(by: { $0.key < $1.key }) {
            arguments += ["--label", "\(key)=\(value)"]
        }
        arguments.append(name)

        let (output, status) = try await runner.run(executable: cli, arguments: arguments)
        guard status == 0 else {
            throw MockerError.operationFailed(
                NetworkManager.errorMessage(from: output, fallback: "failed to create volume \(name)"))
        }
        return try await inspect(name)
    }

    /// Create a directory volume, for data several containers mount at once.
    public func createDirectory(name: String, labels: [String: String] = [:]) throws -> VolumeInfo {
        guard try directoryPath(name) == nil else {
            throw MockerError.operationFailed("volume \(name) already exists")
        }
        let dataPath = "\(storagePath)/\(name)/_data"
        try FileManager.default.createDirectory(atPath: dataPath, withIntermediateDirectories: true)

        let info = VolumeInfo(name: name, mountpoint: dataPath, labels: labels)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(info).write(to: URL(fileURLWithPath: "\(storagePath)/\(name)/meta.json"))
        return info
    }

    /// Native volumes merged with directory ones. A directory volume wins a name
    /// collision, matching what compose mounts for that name.
    public func list() async throws -> [VolumeInfo] {
        var byName: [String: VolumeInfo] = [:]
        for volume in try await nativeVolumes() { byName[volume.name] = volume }
        for volume in directoryVolumes() { byName[volume.name] = volume }
        return byName.values.sorted { $0.name < $1.name }
    }

    /// Remove a volume. A directory volume's directory is deleted; a native one goes
    /// through the runtime, which refuses a volume that is still in use.
    public func remove(_ name: String) async throws -> VolumeInfo {
        let volume = try await inspect(name)

        if try directoryPath(name) != nil {
            try FileManager.default.removeItem(atPath: "\(storagePath)/\(name)")
            return volume
        }

        let (output, status) = try await runner.run(executable: cli, arguments: ["volume", "delete", name])
        guard status == 0 else {
            throw MockerError.operationFailed(
                NetworkManager.errorMessage(from: output, fallback: "failed to remove volume \(name)"))
        }
        return volume
    }

    /// Remove unused native volumes: anonymous ones only, or every one with `all`.
    /// Directory volumes are never pruned, since nothing records whether they are in use.
    /// - Returns: the names actually removed; a volume the runtime refuses (in use) is skipped.
    public func prune(all: Bool) async throws -> [String] {
        let directories = Set(directoryVolumes().map(\.name))
        var removed: [String] = []
        for volume in try await nativeVolumes() where !directories.contains(volume.name) {
            guard all || volume.labels[Self.anonymousLabel] != nil else { continue }
            let (_, status) = try await runner.run(executable: cli, arguments: ["volume", "delete", volume.name])
            if status == 0 { removed.append(volume.name) }
        }
        return removed
    }

    /// Inspect a volume.
    public func inspect(_ name: String) async throws -> VolumeInfo {
        guard let volume = try await list().first(where: { $0.name == name }) else {
            throw MockerError.volumeNotFound(name)
        }
        return volume
    }

    private func nativeVolumes() async throws -> [VolumeInfo] {
        let (output, status) = try await runner.run(executable: cli, arguments: ["volume", "ls", "--format", "json"])
        guard status == 0 else {
            throw MockerError.operationFailed(
                NetworkManager.errorMessage(from: output, fallback: "failed to list volumes"))
        }
        return Self.parseVolumes(output)
    }

    // MARK: - Parsing

    /// Decode `container volume ls --format json`. Unparseable entries are skipped
    /// rather than failing the whole listing.
    static func parseVolumes(_ json: String) -> [VolumeInfo] {
        guard let data = json.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return entries.compactMap { entry in
            let config = entry["configuration"] as? [String: Any] ?? [:]
            guard let name = (config["name"] as? String) ?? (entry["id"] as? String) else { return nil }
            return VolumeInfo(
                name: name,
                driver: config["driver"] as? String ?? "local",
                mountpoint: config["source"] as? String ?? "",
                created: NetworkManager.parseCreationDate(config["creationDate"]) ?? Date(),
                labels: config["labels"] as? [String: String] ?? [:]
            )
        }
    }

    /// Directory volumes: every `<volumesPath>/<name>/_data`, described by its `meta.json`
    /// when that still decodes.
    private func directoryVolumes() -> [VolumeInfo] {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = (try? fm.contentsOfDirectory(atPath: storagePath)) ?? []
        return entries.compactMap { name in
            guard let dataPath = try? directoryPath(name) else { return nil }
            let metaURL = URL(fileURLWithPath: "\(storagePath)/\(name)/meta.json")
            var info = (try? Data(contentsOf: metaURL)).flatMap { try? decoder.decode(VolumeInfo.self, from: $0) }
                ?? VolumeInfo(name: name)
            info.name = name
            info.mountpoint = dataPath
            return info
        }
    }
}
