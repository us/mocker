import ArgumentParser
import MockerKit

struct Exec: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute a command in a running container"
    )

    @Argument(help: "Container name or ID")
    var container: String

    @Argument(help: "Command to execute")
    var command: [String]

    @Flag(name: .short, help: "Keep STDIN open")
    var interactive = false

    @Flag(name: .short, help: "Allocate a pseudo-TTY")
    var tty = false

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Set environment variables")
    var env: [String] = []

    @Option(name: .shortAndLong, help: "Working directory inside the container")
    var workdir: String?

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        try await engine.exec(container, command: command, interactive: interactive, tty: tty)
    }
}
