import ArgumentParser
import MockerKit

struct Start: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start one or more stopped containers"
    )

    @Argument(help: "Container name or ID")
    var containers: [String]

    @Flag(name: .shortAndLong, help: "Attach STDOUT/STDERR and forward signals")
    var attach = false

    @Flag(name: .shortAndLong, help: "Attach container's STDIN")
    var interactive = false

    @Option(name: .customLong("detach-keys"), help: "Override the key sequence for detaching a container")
    var detachKeys: String?

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        for identifier in containers {
            let container = try await engine.start(identifier)
            if attach {
                let lines = try await engine.logs(container.id, follow: true)
                for line in lines {
                    print(line)
                }
            } else {
                print(identifier)
            }
        }
    }
}
