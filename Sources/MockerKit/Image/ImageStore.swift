import Foundation

/// Persists image metadata to disk.
actor ImageStore {
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

    func save(_ image: ImageInfo) throws {
        let data = try encoder.encode(image)
        let safeID = image.id.replacingOccurrences(of: ":", with: "_")
        let filePath = "\(path)/\(safeID).json"
        try data.write(to: URL(fileURLWithPath: filePath))
    }

    func delete(_ id: String) throws {
        let safeID = id.replacingOccurrences(of: ":", with: "_")
        let filePath = "\(path)/\(safeID).json"
        if fm.fileExists(atPath: filePath) {
            try fm.removeItem(atPath: filePath)
        }
    }

    func listAll() throws -> [ImageInfo] {
        guard fm.fileExists(atPath: path) else { return [] }
        let files = try fm.contentsOfDirectory(atPath: path)
            .filter { $0.hasSuffix(".json") }

        return try files.compactMap { file in
            let filePath = "\(path)/\(file)"
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            return try decoder.decode(ImageInfo.self, from: data)
        }
        .sorted { $0.created > $1.created }
    }

    func findByReference(_ reference: String) throws -> ImageInfo? {
        let images = try listAll()

        // Try exact match on reference
        if let match = images.first(where: { $0.reference == reference }) {
            return match
        }

        // Try matching repository only (assumes "latest" tag)
        if let match = images.first(where: { $0.repository == reference }) {
            return match
        }

        // Try matching ID prefix
        if let match = images.first(where: { $0.id.hasPrefix(reference) }) {
            return match
        }

        return nil
    }
}
