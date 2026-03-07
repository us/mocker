import Foundation

/// Runtime information about a container.
public struct ContainerInfo: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var image: String
    public var state: ContainerState
    public var status: String
    public var created: Date
    public var ports: [PortMapping]
    public var labels: [String: String]
    public var command: String
    public var pid: Int?
    /// Container IP address assigned by vmnet (Apple Containerization).
    public var networkAddress: String

    public init(
        id: String,
        name: String,
        image: String,
        state: ContainerState,
        status: String,
        created: Date,
        ports: [PortMapping] = [],
        labels: [String: String] = [:],
        command: String = "",
        pid: Int? = nil,
        networkAddress: String = ""
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.status = status
        self.created = created
        self.ports = ports
        self.labels = labels
        self.command = command
        self.pid = pid
        self.networkAddress = networkAddress
    }

    /// Short ID (first 12 characters).
    public var shortID: String {
        String(id.prefix(12))
    }

    /// Formatted creation time relative to now.
    public var createdAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: created, relativeTo: Date())
    }
}
