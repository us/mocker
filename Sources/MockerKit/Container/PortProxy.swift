import Foundation
import Network

/// Forwards TCP connections from localhost:hostPort to containerIP:containerPort.
/// One instance per port mapping, runs as a background process via `socat` or
/// falls back to a pure-Swift NWListener proxy.
public actor PortProxy {
    private var listeners: [NWListener] = []

    public init() {}

    /// Start forwarding for all port mappings once the container's IP is known.
    public func start(ports: [PortMapping], containerIP: String) async throws {
        for port in ports {
            guard port.hostPort > 0, port.containerPort > 0 else { continue }
            try await startForwarding(
                hostPort: UInt16(port.hostPort),
                containerIP: containerIP,
                containerPort: UInt16(port.containerPort)
            )
        }
    }

    /// Stop all listeners.
    public func stop() {
        for listener in listeners { listener.cancel() }
        listeners.removeAll()
    }

    private func startForwarding(hostPort: UInt16, containerIP: String, containerPort: UInt16) async throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let port = NWEndpoint.Port(rawValue: hostPort) else { return }
        let listener = try NWListener(using: params, on: port)

        listener.newConnectionHandler = { inbound in
            inbound.start(queue: .global())
            let outboundHost = NWEndpoint.Host(containerIP)
            guard let outboundPort = NWEndpoint.Port(rawValue: containerPort) else { return }
            let outbound = NWConnection(host: outboundHost, port: outboundPort, using: .tcp)
            outbound.start(queue: .global())
            Self.pipe(inbound, outbound)
            Self.pipe(outbound, inbound)
        }

        listener.start(queue: .global())
        listeners.append(listener)
    }

    /// Relay data in one direction between two connections.
    private static func pipe(_ from: NWConnection, _ to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { _ in })
            }
            if isComplete || error != nil {
                to.cancel()
                return
            }
            pipe(from, to)
        }
    }
}
