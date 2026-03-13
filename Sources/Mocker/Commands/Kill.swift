import ArgumentParser
import MockerKit

struct Kill: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Kill one or more running containers"
    )

    @Argument(help: "Container name or ID")
    var containers: [String]

    @Option(name: .shortAndLong, help: "Signal to send to the container")
    var signal: String = "KILL"

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        for identifier in containers {
            // kill is essentially a forceful stop
            _ = try await engine.stop(identifier)
            print(identifier)
        }
    }
}
