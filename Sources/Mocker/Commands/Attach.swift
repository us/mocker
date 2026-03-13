import ArgumentParser
import MockerKit

struct Attach: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Attach local standard input, output, and error streams to a running container"
    )

    @Argument(help: "Container name or ID")
    var container: String

    @Option(name: .customLong("detach-keys"), help: "Override the key sequence for detaching a container")
    var detachKeys: String?

    @Flag(name: .customLong("no-stdin"), help: "Do not attach STDIN")
    var noStdin = false

    @Flag(name: .customLong("sig-proxy"), inversion: .prefixedNo, help: "Proxy all received signals to the process")
    var sigProxy = true

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        // Attach is essentially following logs with interactive stdin
        let lines = try await engine.logs(container, follow: true)
        for line in lines {
            print(line)
        }
    }
}
