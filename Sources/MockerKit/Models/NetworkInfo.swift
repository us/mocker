import Foundation

/// Information about a container network.
public struct NetworkInfo: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var driver: String
    public var subnet: String?
    public var gateway: String?
    public var containers: [String]
    public var created: Date
    public var labels: [String: String]

    public init(
        id: String,
        name: String,
        driver: String = "bridge",
        subnet: String? = nil,
        gateway: String? = nil,
        containers: [String] = [],
        created: Date = Date(),
        labels: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.driver = driver
        self.subnet = subnet
        self.gateway = gateway
        self.containers = containers
        self.created = created
        self.labels = labels
    }

    /// Short ID (first 12 characters).
    public var shortID: String {
        String(id.prefix(12))
    }
}
