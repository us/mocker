import ArgumentParser
import MockerKit

struct Pause: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Pause all processes within one or more containers"
    )

    @Argument(help: "Container name or ID")
    var containers: [String]

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        for identifier in containers {
            try await engine.pause(identifier)
            print(identifier)
        }
    }
}

struct Unpause: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Unpause all processes within one or more containers"
    )

    @Argument(help: "Container name or ID")
    var containers: [String]

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        for identifier in containers {
            try await engine.unpause(identifier)
            print(identifier)
        }
    }
}
