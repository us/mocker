import Foundation

/// Manages container images.
public actor ImageManager {
    private let config: MockerConfig
    private let store: ImageStore

    public init(config: MockerConfig = MockerConfig()) throws {
        self.config = config
        self.store = try ImageStore(path: config.imagesPath)
    }

    /// Pull an image from a registry.
    public func pull(_ reference: String) async throws -> ImageInfo {
        let ref = try ImageReference.parse(reference)

        // Return existing image if already pulled
        if let existing = try await store.findByReference("\(ref.fullRepository):\(ref.tag)") {
            return existing
        }

        // TODO: Use Containerization framework to actually pull the image
        // For now, create a placeholder
        let id = generateID()
        let info = ImageInfo(
            id: id,
            repository: ref.fullRepository,
            tag: ref.tag,
            size: 0,
            created: Date()
        )
        try await store.save(info)
        return info
    }

    /// List all local images.
    public func list() async throws -> [ImageInfo] {
        try await store.listAll()
    }

    /// Remove an image.
    public func remove(_ reference: String) async throws -> ImageInfo {
        guard let image = try await store.findByReference(reference) else {
            throw MockerError.imageNotFound(reference)
        }
        try await store.delete(image.id)
        return image
    }

    /// Tag an image with a new reference.
    public func tag(_ source: String, _ target: String) async throws {
        guard let image = try await store.findByReference(source) else {
            throw MockerError.imageNotFound(source)
        }
        let targetRef = try ImageReference.parse(target)
        var tagged = image
        tagged.id = generateID()
        tagged.repository = targetRef.fullRepository
        tagged.tag = targetRef.tag
        try await store.save(tagged)
    }

    /// Inspect an image.
    public func inspect(_ reference: String) async throws -> ImageInfo {
        guard let image = try await store.findByReference(reference) else {
            throw MockerError.imageNotFound(reference)
        }
        return image
    }

    /// Build an image from a Dockerfile.
    public func build(tag: String, context: String, dockerfile: String = "Dockerfile") async throws -> ImageInfo {
        let contextURL = URL(fileURLWithPath: context)
        let dockerfilePath = contextURL.appendingPathComponent(dockerfile).path

        guard FileManager.default.fileExists(atPath: dockerfilePath) else {
            throw MockerError.buildError("Dockerfile not found at \(dockerfilePath)")
        }

        // TODO: Use Containerization framework BuildKit support
        let ref = try ImageReference.parse(tag)
        let id = generateID()
        let info = ImageInfo(
            id: id,
            repository: ref.fullRepository,
            tag: ref.tag,
            size: 0,
            created: Date()
        )
        try await store.save(info)
        return info
    }

    /// Push an image to a registry.
    public func push(_ reference: String) async throws {
        guard try await store.findByReference(reference) != nil else {
            throw MockerError.imageNotFound(reference)
        }
        // TODO: Use Containerization framework to push
    }

    private func generateID() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return "sha256:" + bytes.map { String(format: "%02x", $0) }.joined()
    }
}
