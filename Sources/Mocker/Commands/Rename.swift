import ArgumentParser
import MockerKit

struct Rename: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Rename a container"
    )

    @Argument(help: "Current container name or ID")
    var container: String

    @Argument(help: "New container name")
    var newName: String

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        try await engine.rename(container, to: newName)
    }
}
