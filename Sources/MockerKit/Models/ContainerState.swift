import Foundation

/// Represents the lifecycle state of a container.
public enum ContainerState: String, Codable, Sendable {
    case created
    case running
    case paused
    case stopped
    case exited
    case dead

    public var displayString: String {
        switch self {
        case .created: "Created"
        case .running: "Running"
        case .paused: "Paused"
        case .stopped: "Stopped"
        case .exited: "Exited"
        case .dead: "Dead"
        }
    }

    public var isActive: Bool {
        self == .running || self == .paused
    }
}
