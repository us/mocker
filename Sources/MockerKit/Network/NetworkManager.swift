import Foundation

/// Manages container networks.
public actor NetworkManager {
    private let config: MockerConfig
    private var networks: [String: NetworkInfo] = [:]
    private let storagePath: String

    public init(config: MockerConfig = MockerConfig()) throws {
        self.config = config
        self.storagePath = config.networksPath
        let fm = FileManager.default
        if !fm.fileExists(atPath: storagePath) {
            try fm.createDirectory(atPath: storagePath, withIntermediateDirectories: true)
        }

        // Load persisted networks synchronously during init
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let files = try? fm.contentsOfDirectory(atPath: storagePath).filter({ $0.hasSuffix(".json") }) {
            for file in files {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: "\(storagePath)/\(file)")),
                   let info = try? decoder.decode(NetworkInfo.self, from: data) {
                    networks[info.name] = info
                }
            }
        }
    }

    /// Create a new network.
    public func create(name: String, driver: String = "bridge", subnet: String? = nil, gateway: String? = nil) throws -> NetworkInfo {
        guard networks[name] == nil else {
            throw MockerError.operationFailed("Network \(name) already exists")
        }

        let info = NetworkInfo(
            id: generateID(),
            name: name,
            driver: driver,
            subnet: subnet,
            gateway: gateway,
            created: Date()
        )
        networks[name] = info
        try saveToDisk(info)
        return info
    }

    /// List all networks.
    public func list() -> [NetworkInfo] {
        Array(networks.values).sorted { $0.created > $1.created }
    }

    /// Remove a network.
    public func remove(_ name: String) throws -> NetworkInfo {
        guard let network = networks[name] else {
            throw MockerError.networkNotFound(name)
        }
        guard network.containers.isEmpty else {
            throw MockerError.operationFailed("Network \(name) has active containers")
        }
        networks.removeValue(forKey: name)
        try deleteFromDisk(network.id)
        return network
    }

    /// Inspect a network.
    public func inspect(_ name: String) throws -> NetworkInfo {
        guard let network = networks[name] else {
            throw MockerError.networkNotFound(name)
        }
        return network
    }

    /// Connect a container to a network.
    public func connect(container: String, network: String) throws {
        guard var net = networks[network] else {
            throw MockerError.networkNotFound(network)
        }
        net.containers.append(container)
        networks[network] = net
        try saveToDisk(net)
    }

    /// Disconnect a container from a network.
    public func disconnect(container: String, network: String) throws {
        guard var net = networks[network] else {
            throw MockerError.networkNotFound(network)
        }
        net.containers.removeAll { $0 == container }
        networks[network] = net
        try saveToDisk(net)
    }

    // MARK: - Persistence

    private func loadFromDisk() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storagePath) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let files = try fm.contentsOfDirectory(atPath: storagePath)
            .filter { $0.hasSuffix(".json") }

        for file in files {
            let data = try Data(contentsOf: URL(fileURLWithPath: "\(storagePath)/\(file)"))
            let info = try decoder.decode(NetworkInfo.self, from: data)
            networks[info.name] = info
        }
    }

    private func saveToDisk(_ info: NetworkInfo) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(info)
        try data.write(to: URL(fileURLWithPath: "\(storagePath)/\(info.id).json"))
    }

    private func deleteFromDisk(_ id: String) throws {
        let filePath = "\(storagePath)/\(id).json"
        if FileManager.default.fileExists(atPath: filePath) {
            try FileManager.default.removeItem(atPath: filePath)
        }
    }

    private func generateID() -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
