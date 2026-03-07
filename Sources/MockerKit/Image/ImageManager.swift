import Foundation
import Containerization
import ContainerizationOCI

/// Manages container images using Apple's Containerization framework.
public actor ImageManager {
    private let imageStore: Containerization.ImageStore

    public init(config: MockerConfig = MockerConfig()) throws {
        self.imageStore = try Containerization.ImageStore(path: config.ociStorePath)
    }

    // MARK: - Pull

    /// Pull an image from a registry.
    /// Returns (image, alreadyExisted) so the CLI can show the right status message.
    public func pull(_ reference: String) async throws -> (ImageInfo, Bool) {
        let normalized = try Self.normalize(reference)

        // Check if already present
        if let existing = try? await imageStore.get(reference: normalized) {
            return (Self.toImageInfo(existing), true)
        }

        let image = try await imageStore.pull(reference: normalized, platform: .arm64)
        return (Self.toImageInfo(image), false)
    }

    // MARK: - List

    /// List all local images.
    public func list() async throws -> [ImageInfo] {
        let images = try await imageStore.list()
        return images.map(Self.toImageInfo)
    }

    // MARK: - Remove

    /// Remove an image by reference.
    public func remove(_ reference: String) async throws -> ImageInfo {
        let normalized = try Self.normalize(reference)
        guard let image = try? await imageStore.get(reference: normalized) else {
            throw MockerError.imageNotFound(reference)
        }
        let info = Self.toImageInfo(image)
        try await imageStore.delete(reference: normalized)
        return info
    }

    // MARK: - Tag

    /// Tag an image with a new reference.
    public func tag(_ source: String, _ target: String) async throws {
        let src = try Self.normalize(source)
        let dst = try Self.normalize(target)
        _ = try await imageStore.tag(existing: src, new: dst)
    }

    // MARK: - Inspect

    /// Inspect an image.
    public func inspect(_ reference: String) async throws -> ImageInfo {
        let normalized = try Self.normalize(reference)
        guard let image = try? await imageStore.get(reference: normalized) else {
            throw MockerError.imageNotFound(reference)
        }
        return Self.toImageInfo(image)
    }

    // MARK: - Build

    /// Build an image from a Dockerfile.
    /// Real BuildKit integration is a TODO — validates Dockerfile exists and registers metadata.
    public func build(tag: String, context: String, dockerfile: String = "Dockerfile") async throws -> ImageInfo {
        let contextURL = URL(fileURLWithPath: context)
        let dockerfilePath = contextURL.appendingPathComponent(dockerfile).path

        guard FileManager.default.fileExists(atPath: dockerfilePath) else {
            throw MockerError.buildError("Dockerfile not found at \(dockerfilePath)")
        }

        // TODO: Use Containerization BuildKit support when available
        // For now return a placeholder — image operations work, build does not
        let ref = try ImageReference.parse(tag)
        let fakeDigest = "sha256:" + (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let info = ImageInfo(
            id: fakeDigest,
            repository: ref.fullRepository,
            tag: ref.tag,
            size: 0,
            created: Date()
        )
        return info
    }

    // MARK: - Push

    /// Push an image to a registry.
    public func push(_ reference: String) async throws {
        let normalized = try Self.normalize(reference)
        guard (try? await imageStore.get(reference: normalized)) != nil else {
            throw MockerError.imageNotFound(reference)
        }
        try await imageStore.push(reference: normalized, platform: .arm64)
    }

    // MARK: - Save / Load

    /// Save images to an OCI tar archive.
    public func save(references: [String], to outputPath: String) async throws {
        let normalizedRefs = try references.map { try Self.normalize($0) }
        let outputURL = URL(fileURLWithPath: outputPath)
        try await imageStore.save(references: normalizedRefs, out: outputURL)
    }

    /// Load images from an OCI tar archive.
    public func load(from inputPath: String) async throws -> [ImageInfo] {
        let inputURL = URL(fileURLWithPath: inputPath)
        let images = try await imageStore.load(from: inputURL)
        return images.map(Self.toImageInfo)
    }

    // MARK: - Helpers

    private static func normalize(_ reference: String) throws -> String {
        // ContainerizationOCI.Reference.parse requires a fully-qualified reference with domain.
        // Docker-style short references ("alpine", "nginx:1.25", "user/image:tag") need a domain.
        var fullRef = reference
        let parts = reference.split(separator: "/", maxSplits: 1)
        if parts.count == 1 {
            // No slash → single name like "alpine:latest"
            fullRef = "docker.io/library/\(reference)"
        } else {
            let domain = String(parts[0])
            // Domain must contain a dot, colon, or be "localhost"
            let looksLikeDomain = domain.contains(".") || domain.contains(":") || domain == "localhost"
            if !looksLikeDomain {
                // e.g. "myuser/myimage:tag" — no domain, add docker.io
                fullRef = "docker.io/\(reference)"
            }
        }
        let ref = try ContainerizationOCI.Reference.parse(fullRef)
        ref.normalize()
        return ref.description
    }

    private static func toImageInfo(_ image: Containerization.Image) -> ImageInfo {
        // Parse repo and tag from the reference string
        let ref = try? ImageReference.parse(image.reference)
        let repository = ref?.fullRepository ?? image.reference
        let tag = ref?.tag ?? "latest"

        return ImageInfo(
            id: image.digest,
            repository: repository,
            tag: tag,
            size: 0,         // Size requires reading all layer blobs — expensive
            created: Date()  // Created requires reading image config — async
        )
    }
}

extension ContainerizationOCI.Platform {
    static var arm64: ContainerizationOCI.Platform {
        .init(arch: "arm64", os: "linux", variant: "v8")
    }
}
