import ArgumentParser
import MockerKit

struct Logs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Fetch the logs of a container"
    )

    @Argument(help: "Container name or ID")
    var container: String

    @Flag(name: .shortAndLong, help: "Follow log output")
    var follow = false

    @Option(name: .long, help: "Number of lines to show from the end")
    var tail: Int?

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        let lines = try await engine.logs(container, follow: follow, tail: tail)

        for line in lines {
            print(line)
        }
    }
}
