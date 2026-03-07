import Foundation

/// Information about a container image.
public struct ImageInfo: Codable, Sendable, Identifiable {
    public var id: String
    public var repository: String
    public var tag: String
    public var size: UInt64
    public var created: Date
    public var labels: [String: String]

    public init(
        id: String,
        repository: String,
        tag: String = "latest",
        size: UInt64 = 0,
        created: Date = Date(),
        labels: [String: String] = [:]
    ) {
        self.id = id
        self.repository = repository
        self.tag = tag
        self.size = size
        self.created = created
        self.labels = labels
    }

    /// Short ID (first 12 characters).
    public var shortID: String {
        String(id.prefix(12))
    }

    /// Full image reference (repository:tag).
    public var reference: String {
        "\(repository):\(tag)"
    }

    /// Human-readable size string.
    public var sizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// Formatted creation time relative to now.
    public var createdAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: created, relativeTo: Date())
    }
}

/// Reference to an image with optional registry, repository, and tag.
public struct ImageReference: Sendable {
    public var registry: String?
    public var repository: String
    public var tag: String

    public init(registry: String? = nil, repository: String, tag: String = "latest") {
        self.registry = registry
        self.repository = repository
        self.tag = tag
    }

    /// Parse an image reference string like "nginx", "nginx:1.25", or "registry.example.com/myapp:v1".
    public static func parse(_ value: String) throws -> ImageReference {
        var remaining = value
        var registry: String?

        // Check if first component contains a dot or colon (indicating a registry)
        let components = remaining.split(separator: "/", maxSplits: 1)
        if components.count > 1 {
            let first = String(components[0])
            if first.contains(".") || first.contains(":") {
                registry = first
                remaining = String(components[1])
            }
        }

        // Split repository:tag
        let tagParts = remaining.split(separator: ":", maxSplits: 1)
        guard !tagParts.isEmpty else {
            throw MockerError.invalidImageReference(value)
        }
        let repository = String(tagParts[0])
        let tag = tagParts.count > 1 ? String(tagParts[1]) : "latest"

        guard !repository.isEmpty else {
            throw MockerError.invalidImageReference(value)
        }

        return ImageReference(registry: registry, repository: repository, tag: tag)
    }

    /// Repository with registry prefix if present.
    public var fullRepository: String {
        if let registry {
            return "\(registry)/\(repository)"
        }
        return repository
    }

    /// Full reference string.
    public var fullReference: String {
        var result = ""
        if let registry {
            result += "\(registry)/"
        }
        result += repository
        result += ":\(tag)"
        return result
    }
}
