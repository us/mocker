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

        let results = try await engine.stats(containerIDs: containers)

        let headers = ["Container ID", "Name", "CPU %", "Mem Usage / Limit", "Mem %", "Net I/O", "Block I/O", "PIDs"]
        let rows = results.map { (c, s) in
            let memPct = s.memLimit > 0 ? (Double(s.memUsage) / Double(s.memLimit) * 100) : 0
            return [
                c.shortID,
                c.name,
                String(format: "%.2f%%", s.cpuPercent),
                "\(formatBytes(s.memUsage)) / \(formatBytes(s.memLimit))",
                String(format: "%.2f%%", memPct),
                "\(formatBytes(s.netIn)) / \(formatBytes(s.netOut))",
                "\(formatBytes(s.blockIn)) / \(formatBytes(s.blockOut))",
                "\(s.pids)",
            ]
        }
        TableFormatter.print(headers: headers, rows: rows)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return String(format: value < 10 ? "%.2f%@" : "%.1f%@", value, units[unit])
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
