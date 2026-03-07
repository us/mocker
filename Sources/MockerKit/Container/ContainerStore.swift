import Foundation

/// Persists container metadata to disk as JSON files.
actor ContainerStore {
    private let path: String
    private let fm = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(path: String) throws {
        self.path = path
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        if !fm.fileExists(atPath: path) {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }

    func save(_ container: ContainerInfo) throws {
        let data = try encoder.encode(container)
        let filePath = "\(path)/\(container.id).json"
        try data.write(to: URL(fileURLWithPath: filePath))
    }

    func load(_ id: String) throws -> ContainerInfo? {
        let filePath = "\(path)/\(id).json"
        guard fm.fileExists(atPath: filePath) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        return try decoder.decode(ContainerInfo.self, from: data)
    }

    func delete(_ id: String) throws {
        let filePath = "\(path)/\(id).json"
        if fm.fileExists(atPath: filePath) {
            try fm.removeItem(atPath: filePath)
        }
    }

    func listAll() throws -> [ContainerInfo] {
        guard fm.fileExists(atPath: path) else { return [] }
        let files = try fm.contentsOfDirectory(atPath: path)
            .filter { $0.hasSuffix(".json") }

        return try files.compactMap { file in
            let filePath = "\(path)/\(file)"
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            return try decoder.decode(ContainerInfo.self, from: data)
        }
        .sorted { $0.created > $1.created }
    }

    func findByName(_ name: String) throws -> ContainerInfo? {
        try listAll().first { $0.name == name }
    }

    func findByIDPrefix(_ prefix: String) throws -> ContainerInfo? {
        try listAll().first { $0.id.hasPrefix(prefix) }
    }
}
