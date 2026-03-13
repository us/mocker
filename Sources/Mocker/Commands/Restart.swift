import ArgumentParser
import MockerKit

struct Restart: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Restart one or more containers"
    )

    @Argument(help: "Container name or ID")
    var containers: [String]

    @Option(name: .shortAndLong, help: "Seconds to wait before killing the container")
    var timeout: Int = 10

    @Option(name: .shortAndLong, help: "Signal to send to the container")
    var signal: String?

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        for identifier in containers {
            _ = try await engine.stop(identifier)
            _ = try await engine.start(identifier)
            print(identifier)
        }
    }
}
