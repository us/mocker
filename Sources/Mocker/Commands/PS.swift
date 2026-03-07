import ArgumentParser
import MockerKit

struct PS: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ps",
        abstract: "List containers"
    )

    @Flag(name: .shortAndLong, help: "Show all containers (default shows just running)")
    var all = false

    @Flag(name: .shortAndLong, help: "Only display container IDs")
    var quiet = false

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        let containers = try await engine.list(all: all)

        if quiet {
            for container in containers {
                print(container.shortID)
            }
            return
        }

        let headers = ["Container ID", "Image", "Command", "Created", "Status", "Ports", "Names"]
        let rows = containers.map { c in
            [
                c.shortID,
                c.image,
                c.command.isEmpty ? "" : "\"\(c.command)\"",
                c.createdAgo,
                c.status,
                c.ports.map(\.description).joined(separator: ", "),
                c.name,
            ]
        }
        TableFormatter.print(headers: headers, rows: rows)
    }
}
