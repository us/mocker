import Foundation

/// Manages persistent volumes.
public actor VolumeManager {
    private let config: MockerConfig
    private var volumes: [String: VolumeInfo] = [:]
    private let storagePath: String

    public init(config: MockerConfig = MockerConfig()) throws {
        self.config = config
        self.storagePath = config.volumesPath
        let fm = FileManager.default
        if !fm.fileExists(atPath: storagePath) {
            try fm.createDirectory(atPath: storagePath, withIntermediateDirectories: true)
        }

        // Load persisted volumes synchronously during init
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let entries = try? fm.contentsOfDirectory(atPath: storagePath) {
            for entry in entries {
                let metaPath = "\(storagePath)/\(entry)/meta.json"
                if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                   let info = try? decoder.decode(VolumeInfo.self, from: data) {
                    volumes[info.name] = info
                }
            }
        }
    }

    /// Create a new volume.
    public func create(name: String, driver: String = "local", labels: [String: String] = [:]) throws -> VolumeInfo {
        guard volumes[name] == nil else {
            throw MockerError.operationFailed("Volume \(name) already exists")
        }

        let mountpoint = "\(config.volumesPath)/\(name)/_data"
        let fm = FileManager.default
        if !fm.fileExists(atPath: mountpoint) {
            try fm.createDirectory(atPath: mountpoint, withIntermediateDirectories: true)
        }

        let info = VolumeInfo(
            name: name,
            driver: driver,
            mountpoint: mountpoint,
            created: Date(),
            labels: labels
        )
        volumes[name] = info
        try saveMeta(info)
        return info
    }

    /// List all volumes, filtering out stale entries where _data/ no longer exists.
    public func list() -> [VolumeInfo] {
        let fm = FileManager.default
        var stale: [String] = []
        for (name, vol) in volumes {
            if !fm.fileExists(atPath: vol.mountpoint) {
                stale.append(name)
            }
        }
        for name in stale {
            volumes.removeValue(forKey: name)
        }
        return Array(volumes.values).sorted { $0.name < $1.name }
    }

    /// Remove a volume.
    public func remove(_ name: String) throws -> VolumeInfo {
        guard let vol = volumes[name] else {
            throw MockerError.volumeNotFound(name)
        }
        volumes.removeValue(forKey: name)

        let volPath = "\(config.volumesPath)/\(name)"
        if FileManager.default.fileExists(atPath: volPath) {
            try FileManager.default.removeItem(atPath: volPath)
        }
        return vol
    }

    /// Inspect a volume.
    public func inspect(_ name: String) throws -> VolumeInfo {
        guard let vol = volumes[name] else {
            throw MockerError.volumeNotFound(name)
        }
        return vol
    }

    // MARK: - Persistence

    private func loadFromDisk() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storagePath) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let entries = try fm.contentsOfDirectory(atPath: storagePath)
        for entry in entries {
            let metaPath = "\(storagePath)/\(entry)/meta.json"
            guard fm.fileExists(atPath: metaPath) else { continue }
            let data = try Data(contentsOf: URL(fileURLWithPath: metaPath))
            let info = try decoder.decode(VolumeInfo.self, from: data)
            volumes[info.name] = info
        }
    }

    private func saveMeta(_ info: VolumeInfo) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(info)
        let metaDir = "\(config.volumesPath)/\(info.name)"
        let fm = FileManager.default
        if !fm.fileExists(atPath: metaDir) {
            try fm.createDirectory(atPath: metaDir, withIntermediateDirectories: true)
        }
        try data.write(to: URL(fileURLWithPath: "\(metaDir)/meta.json"))
    }
}
