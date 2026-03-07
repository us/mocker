import ArgumentParser
import MockerKit

struct Stats: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Display a live stream of container resource usage statistics"
    )

    @Argument(help: "Container names or IDs (shows all if empty)")
    var containers: [String] = []

    @Flag(name: .long, help: "Disable streaming stats and only pull the first result")
    var noStream = false

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        let allContainers: [ContainerInfo]
        if containers.isEmpty {
            allContainers = try await engine.list()
        } else {
            allContainers = try await containers.asyncMap { id in
                try await engine.inspect(id)
            }
        }

        let headers = ["Container ID", "Name", "CPU %", "Mem Usage / Limit", "Mem %", "Net I/O", "Block I/O", "PIDs"]
        let rows = allContainers.map { c in
            [
                c.shortID,
                c.name,
                "0.00%",       // TODO: Real CPU stats
                "0B / 0B",     // TODO: Real memory stats
                "0.00%",       // TODO: Real memory percentage
                "0B / 0B",     // TODO: Real network I/O
                "0B / 0B",     // TODO: Real block I/O
                "0",           // TODO: Real PID count
            ]
        }
        TableFormatter.print(headers: headers, rows: rows)
    }
}

extension Array where Element: Sendable {
    func asyncMap<T: Sendable>(_ transform: @Sendable (Element) async throws -> T) async throws -> [T] {
        var results: [T] = []
        for element in self {
            try await results.append(transform(element))
        }
        return results
    }
}
