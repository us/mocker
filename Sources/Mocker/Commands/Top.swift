import ArgumentParser
import MockerKit

struct Top: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Display the running processes of a container"
    )

    @Argument(help: "Container name or ID")
    var container: String

    @Argument(help: "ps options (default: -ef)")
    var psArgs: [String] = []

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        let args = psArgs.isEmpty ? ["-ef"] : psArgs
        let output = try await engine.top(container, psArgs: args)
        print(output)
    }
}
