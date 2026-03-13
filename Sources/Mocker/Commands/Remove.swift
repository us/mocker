import ArgumentParser
import MockerKit

struct Remove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove one or more containers"
    )

    @Argument(help: "Container name or ID")
    var containers: [String]

    @Flag(name: .shortAndLong, help: "Force remove running containers")
    var force = false

    @Flag(name: .shortAndLong, help: "Remove the specified link")
    var link = false

    @Flag(name: .shortAndLong, help: "Remove anonymous volumes associated with the container")
    var volumes = false

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        for identifier in containers {
            _ = try await engine.remove(identifier, force: force)
            // Docker echoes back exactly what the user provided
            print(identifier)
        }
    }
}
