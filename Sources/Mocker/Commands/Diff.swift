import ArgumentParser
import MockerKit

struct Diff: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect changes to files or directories on a container's filesystem"
    )

    @Argument(help: "Container name or ID")
    var container: String

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        let changes = try await engine.diff(container)
        for change in changes {
            print(change)
        }
    }
}
