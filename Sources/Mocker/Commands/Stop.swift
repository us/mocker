import ArgumentParser
import MockerKit

struct Stop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop one or more running containers"
    )

    @Argument(help: "Container name or ID")
    var containers: [String]

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        for identifier in containers {
            _ = try await engine.stop(identifier)
            // Docker echoes back exactly what the user provided
            print(identifier)
        }
    }
}
