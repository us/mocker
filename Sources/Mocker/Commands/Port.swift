import ArgumentParser
import MockerKit

struct Port: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List port mappings or a specific mapping for the container"
    )

    @Argument(help: "Container name or ID")
    var container: String

    @Argument(help: "Private port (e.g. 80/tcp)")
    var privatePort: String?

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        let info = try await engine.inspect(container)

        for port in info.ports {
            if let privatePort {
                let parts = privatePort.split(separator: "/")
                let portNum = UInt16(parts[0]) ?? 0
                if port.containerPort == portNum {
                    print("0.0.0.0:\(port.hostPort)")
                }
            } else {
                print("\(port.containerPort)/\(port.portProtocol.rawValue) -> 0.0.0.0:\(port.hostPort)")
            }
        }
    }
}
