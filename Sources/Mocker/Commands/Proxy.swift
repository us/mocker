import ArgumentParser
import Foundation
import Network

/// Internal hidden command — runs a persistent TCP proxy in the foreground.
/// Spawned as a detached background process by ContainerEngine when port mappings exist.
/// Usage: mocker __proxy --host-port 9090 --container-ip 192.168.64.2 --container-port 80
struct Proxy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "__proxy",
        abstract: "Internal: persistent TCP port forwarder",
        shouldDisplay: false
    )

    @Option var hostPort: UInt16
    @Option var containerIP: String
    @Option var containerPort: UInt16

    func run() async throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let port = NWEndpoint.Port(rawValue: hostPort) else {
            throw ExitCode.failure
        }

        let listener = try NWListener(using: params, on: port)

        listener.newConnectionHandler = { inbound in
            inbound.start(queue: .global())
            guard let outPort = NWEndpoint.Port(rawValue: self.containerPort) else { return }
            let outbound = NWConnection(
                host: NWEndpoint.Host(self.containerIP),
                port: outPort,
                using: .tcp
            )
            outbound.start(queue: .global())
            Self.relay(inbound, to: outbound)
            Self.relay(outbound, to: inbound)
        }

        listener.start(queue: .global())

        // Run forever (killed by stop/rm via SIGTERM)
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
    }

    private static func relay(_ from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { _ in })
            }
            if isComplete || error != nil {
                to.cancel()
                return
            }
            relay(from, to: to)
        }
    }
}
