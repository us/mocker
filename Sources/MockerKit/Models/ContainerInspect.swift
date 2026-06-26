import Foundation

// MARK: - Docker-Compatible ContainerInspect DTOs

/// Docker-compatible `container inspect` output (mirrors `docker container inspect`).
/// Serializes with Docker PascalCase JSON keys; optional fields are omitted when absent.
///
/// Populated from the data mocker tracks in `ContainerInfo`. Fields that Apple's
/// Containerization runtime does not surface (HostConfig, Mounts, RestartCount, env,
/// exit code, start/finish timestamps, …) are omitted rather than fabricated.
public struct ContainerInspect: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case created = "Created"
        case name = "Name"
        case image = "Image"
        case state = "State"
        case config = "Config"
        case networkSettings = "NetworkSettings"
    }

    public let id: String
    /// RFC3339 timestamp string — Docker emits a string, not a number.
    public let created: String
    /// Docker prefixes the container name with "/".
    public let name: String
    public let image: String
    public let state: ContainerInspectState
    public let config: ContainerInspectConfig
    public let networkSettings: ContainerInspectNetworkSettings

    public init(
        id: String,
        created: String,
        name: String,
        image: String,
        state: ContainerInspectState,
        config: ContainerInspectConfig,
        networkSettings: ContainerInspectNetworkSettings
    ) {
        self.id = id
        self.created = created
        self.name = name
        self.image = image
        self.state = state
        self.config = config
        self.networkSettings = networkSettings
    }
}

/// Docker-compatible `State` sub-object.
public struct ContainerInspectState: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case status = "Status"
        case running = "Running"
        case paused = "Paused"
        case restarting = "Restarting"
        case oomKilled = "OOMKilled"
        case dead = "Dead"
        case pid = "Pid"
    }

    /// One of Docker's status values: created, running, paused, restarting, removing, exited, dead.
    public let status: String
    public let running: Bool
    public let paused: Bool
    public let restarting: Bool
    public let oomKilled: Bool
    public let dead: Bool
    /// 0 when the container is not running (Docker parity).
    public let pid: Int

    public init(
        status: String,
        running: Bool,
        paused: Bool,
        restarting: Bool,
        oomKilled: Bool,
        dead: Bool,
        pid: Int
    ) {
        self.status = status
        self.running = running
        self.paused = paused
        self.restarting = restarting
        self.oomKilled = oomKilled
        self.dead = dead
        self.pid = pid
    }
}

/// Docker-compatible `Config` sub-object. Optional fields are omitted when absent.
public struct ContainerInspectConfig: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case hostname = "Hostname"
        case image = "Image"
        case cmd = "Cmd"
        case labels = "Labels"
    }

    public let hostname: String?
    public let image: String
    public let cmd: [String]?
    public let labels: [String: String]?

    public init(hostname: String? = nil, image: String, cmd: [String]? = nil, labels: [String: String]? = nil) {
        self.hostname = hostname
        self.image = image
        self.cmd = cmd
        self.labels = labels
    }
}

/// Docker-compatible `NetworkSettings` sub-object.
public struct ContainerInspectNetworkSettings: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case ipAddress = "IPAddress"
        case ports = "Ports"
    }

    public let ipAddress: String
    /// Docker shape: `"80/tcp": [ { "HostIp": "0.0.0.0", "HostPort": "8080" } ]`.
    public let ports: [String: [ContainerInspectPortBinding]]?

    public init(ipAddress: String, ports: [String: [ContainerInspectPortBinding]]? = nil) {
        self.ipAddress = ipAddress
        self.ports = ports
    }
}

/// One host binding inside Docker's `NetworkSettings.Ports` map.
public struct ContainerInspectPortBinding: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case hostIp = "HostIp"
        case hostPort = "HostPort"
    }

    public let hostIp: String
    public let hostPort: String

    public init(hostIp: String, hostPort: String) {
        self.hostIp = hostIp
        self.hostPort = hostPort
    }
}

// MARK: - Pure Mapping Function

/// Maps mocker's internal `ContainerInfo` to a Docker-compatible `ContainerInspect`. Pure, no I/O.
public func mapToContainerInspect(_ info: ContainerInfo) -> ContainerInspect {
    let state = ContainerInspectState(
        status: dockerStatus(info.state),
        running: info.state == .running,
        paused: info.state == .paused,
        restarting: false,
        oomKilled: false,
        dead: info.state == .dead,
        pid: info.pid ?? 0
    )

    let config = ContainerInspectConfig(
        image: info.image,
        // ponytail: ContainerInfo keeps only the joined command, so argv quoting isn't
        // preserved — split on whitespace for the common case. Thread real argv if needed.
        cmd: info.command.isEmpty ? nil : info.command.split(separator: " ").map(String.init),
        labels: info.labels.isEmpty ? nil : info.labels
    )

    let ports: [String: [ContainerInspectPortBinding]]? = info.ports.isEmpty ? nil : Dictionary(
        info.ports.map { port in
            (
                "\(port.containerPort)/\(port.portProtocol.rawValue)",
                [ContainerInspectPortBinding(hostIp: "0.0.0.0", hostPort: String(port.hostPort))]
            )
        },
        uniquingKeysWith: { first, _ in first }
    )

    let networkSettings = ContainerInspectNetworkSettings(
        ipAddress: info.networkAddress,
        ports: ports
    )

    return ContainerInspect(
        id: info.id,
        created: rfc3339String(info.created),
        name: "/\(info.name)",
        image: info.image,
        state: state,
        config: config,
        networkSettings: networkSettings
    )
}

/// Maps mocker's `ContainerState` to a Docker `State.Status` string.
/// Docker has no `stopped` status; the closest equivalent is `exited`.
private func dockerStatus(_ state: ContainerState) -> String {
    switch state {
    case .stopped: return "exited"
    default: return state.rawValue
    }
}

private func rfc3339String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
