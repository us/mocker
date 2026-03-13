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

    @Flag(name: .shortAndLong, help: "Keep STDIN open even if not attached")
    var interactive = false

    @Flag(name: .shortAndLong, help: "Allocate a pseudo-TTY")
    var tty = false

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Set environment variables")
    var env: [String] = []

    @Option(name: .shortAndLong, help: "Working directory inside the container")
    var workdir: String?

    @Flag(name: .shortAndLong, help: "Detached mode: run command in the background")
    var detach = false

    @Option(name: .customLong("detach-keys"), help: "Override the key sequence for detaching a container")
    var detachKeys: String?

    @Option(name: .shortAndLong, help: "Username or UID")
    var user: String?

    @Option(name: .customLong("env-file"), parsing: .singleValue, help: "Read in a file of environment variables")
    var envFile: [String] = []

    @Flag(name: .long, help: "Give extended privileges to the command")
    var privileged = false

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        try await engine.exec(container, command: command, interactive: interactive, tty: tty)
    }
}
