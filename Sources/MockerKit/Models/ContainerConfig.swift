import Foundation

/// Configuration for creating a new container.
public struct ContainerConfig: Codable, Sendable {
    public var name: String?
    public var image: String
    public var command: [String]
    public var environment: [String: String]
    public var ports: [PortMapping]
    public var volumes: [VolumeMount]
    public var network: String?
    public var detach: Bool
    public var interactive: Bool
    public var tty: Bool
    public var labels: [String: String]
    public var workingDir: String?
    public var hostname: String?
    public var restartPolicy: RestartPolicy
    public var user: String?
    public var entrypoint: String?
    public var platform: String?
    public var dns: [String]
    public var addHost: [String]
    public var privileged: Bool
    public var capAdd: [String]
    public var capDrop: [String]
    public var readOnly: Bool
    public var tmpfs: [String]
    public var shmSize: String?
    public var stopSignal: String
    public var stopTimeout: Int?
    public var memory: String?
    public var cpus: String?

    public init(
        name: String? = nil,
        image: String,
        command: [String] = [],
        environment: [String: String] = [:],
        ports: [PortMapping] = [],
        volumes: [VolumeMount] = [],
        network: String? = nil,
        detach: Bool = false,
        interactive: Bool = false,
        tty: Bool = false,
        labels: [String: String] = [:],
        workingDir: String? = nil,
        hostname: String? = nil,
        restartPolicy: RestartPolicy = .no,
        user: String? = nil,
        entrypoint: String? = nil,
        platform: String? = nil,
        dns: [String] = [],
        addHost: [String] = [],
        privileged: Bool = false,
        capAdd: [String] = [],
        capDrop: [String] = [],
        readOnly: Bool = false,
        tmpfs: [String] = [],
        shmSize: String? = nil,
        stopSignal: String = "SIGTERM",
        stopTimeout: Int? = nil,
        memory: String? = nil,
        cpus: String? = nil
    ) {
        self.name = name
        self.image = image
        self.command = command
        self.environment = environment
        self.ports = ports
        self.volumes = volumes
        self.network = network
        self.detach = detach
        self.interactive = interactive
        self.tty = tty
        self.labels = labels
        self.workingDir = workingDir
        self.hostname = hostname
        self.restartPolicy = restartPolicy
        self.user = user
        self.entrypoint = entrypoint
        self.platform = platform
        self.dns = dns
        self.addHost = addHost
        self.privileged = privileged
        self.capAdd = capAdd
        self.capDrop = capDrop
        self.readOnly = readOnly
        self.tmpfs = tmpfs
        self.shmSize = shmSize
        self.stopSignal = stopSignal
        self.stopTimeout = stopTimeout
        self.memory = memory
        self.cpus = cpus
    }
}

/// Port mapping between host and container.
public struct PortMapping: Codable, Sendable, CustomStringConvertible {
    public var hostPort: UInt16
    public var containerPort: UInt16
    public var portProtocol: PortProtocol

    public init(hostPort: UInt16, containerPort: UInt16, portProtocol: PortProtocol = .tcp) {
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.portProtocol = portProtocol
    }

    public var description: String {
        "\(hostPort):\(containerPort)/\(portProtocol.rawValue)"
    }

    /// Parse a port mapping string like "8080:80" or "8080:80/udp".
    public static func parse(_ value: String) throws -> PortMapping {
        let parts = value.split(separator: "/")
        let proto: PortProtocol = parts.count > 1 ? (parts[1] == "udp" ? .udp : .tcp) : .tcp

        let portParts = parts[0].split(separator: ":")
        guard portParts.count == 2,
              let host = UInt16(portParts[0]),
              let container = UInt16(portParts[1])
        else {
            throw MockerError.invalidPortMapping(value)
        }

        return PortMapping(hostPort: host, containerPort: container, portProtocol: proto)
    }
}

public enum PortProtocol: String, Codable, Sendable {
    case tcp
    case udp
}

/// Volume mount specification.
public struct VolumeMount: Codable, Sendable, CustomStringConvertible {
    public var source: String
    public var destination: String
    public var readOnly: Bool

    public init(source: String, destination: String, readOnly: Bool = false) {
        self.source = source
        self.destination = destination
        self.readOnly = readOnly
    }

    public var description: String {
        var result = "\(source):\(destination)"
        if readOnly { result += ":ro" }
        return result
    }

    /// Parse a volume mount string.
    /// Supported formats:
    /// - `/host/path:/container/path` (bind mount)
    /// - `/host/path:/container/path:ro` (read-only bind mount)
    /// - `name:/container/path` (named volume)
    /// - `/container/path` (anonymous volume)
    public static func parse(_ value: String) throws -> VolumeMount {
        let parts = value.split(separator: ":", maxSplits: 2).map(String.init)

        if parts.count == 1 {
            // Anonymous volume: just a container path
            return VolumeMount(source: "", destination: parts[0], readOnly: false)
        }

        guard parts.count >= 2 else {
            throw MockerError.invalidVolumeMount(value)
        }
        let readOnly = parts.count > 2 && parts[2] == "ro"
        return VolumeMount(source: parts[0], destination: parts[1], readOnly: readOnly)
    }
}

/// Container restart policy.
public enum RestartPolicy: String, Codable, Sendable {
    case no
    case always
    case onFailure = "on-failure"
    case unlessStopped = "unless-stopped"
}
