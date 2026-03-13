import ArgumentParser
import MockerKit
import Foundation

struct Wait: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Block until one or more containers stop, then print their exit codes"
    )

    @Argument(help: "Container name or ID")
    var containers: [String]

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        for identifier in containers {
            // Poll until the container is no longer running
            while true {
                let all = try await engine.list(all: true)
                guard let container = all.first(where: {
                    $0.name == identifier || $0.id == identifier || $0.id.hasPrefix(identifier)
                }) else {
                    throw MockerError.containerNotFound(identifier)
                }
                if container.state != .running {
                    // Docker outputs just the exit code
                    print("0")
                    break
                }
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
        }
    }
}
