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

    @Option(name: [.customShort("n"), .long], help: "Number of lines to show from the end of the logs")
    var tail: Int?

    @Option(name: .long, help: "Show logs since timestamp (e.g. 2021-01-01T00:00:00Z)")
    var since: String?

    @Option(name: .long, help: "Show logs before a timestamp")
    var until: String?

    @Flag(name: .shortAndLong, help: "Show timestamps")
    var timestamps = false

    @Flag(name: .long, help: "Show extra details provided to logs")
    var details = false

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        let lines = try await engine.logs(container, follow: follow, tail: tail)

        for line in lines {
            print(line)
        }
    }
}
