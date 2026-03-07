import Foundation

/// Information about a storage volume.
public struct VolumeInfo: Codable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var driver: String
    public var mountpoint: String
    public var created: Date
    public var labels: [String: String]

    public init(
        name: String,
        driver: String = "local",
        mountpoint: String = "",
        created: Date = Date(),
        labels: [String: String] = [:]
    ) {
        self.name = name
        self.driver = driver
        self.mountpoint = mountpoint
        self.created = created
        self.labels = labels
    }
}
