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

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Filter output based on conditions provided")
    var filter: [String] = []

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    @Flag(name: .customLong("no-trunc"), help: "Don't truncate output")
    var noTrunc = false

    @Option(name: [.customShort("n"), .long], help: "Show n last created containers (includes all states)")
    var last: Int?

    @Flag(name: .shortAndLong, help: "Show the latest created container (includes all states)")
    var latest = false

    @Flag(name: .shortAndLong, help: "Display total file sizes")
    var size = false

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        var containers = try await engine.list(all: all)

        // Apply filters
        for f in filter {
            let parts = f.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1])
            switch key {
            case "name":
                containers = containers.filter { $0.name.contains(value) }
            case "status":
                containers = containers.filter { $0.state.rawValue == value }
            case "id":
                containers = containers.filter { $0.id.hasPrefix(value) }
            case "label":
                let labelParts = value.split(separator: "=", maxSplits: 1)
                if labelParts.count == 2 {
                    containers = containers.filter { $0.labels[String(labelParts[0])] == String(labelParts[1]) }
                } else {
                    containers = containers.filter { $0.labels[value] != nil }
                }
            case "ancestor":
                containers = containers.filter { $0.image == value || $0.image.hasPrefix(value) }
            default:
                break
            }
        }

        // Apply --latest / --last
        if latest {
            containers = Array(containers.prefix(1))
        } else if let last {
            containers = Array(containers.prefix(last))
        }

        if quiet {
            for container in containers {
                print(noTrunc ? container.id : container.shortID)
            }
            return
        }

        if let format {
            for c in containers {
                var output = format
                output = output.replacingOccurrences(of: "{{.ID}}", with: noTrunc ? c.id : c.shortID)
                output = output.replacingOccurrences(of: "{{.Image}}", with: c.image)
                output = output.replacingOccurrences(of: "{{.Command}}", with: c.command)
                output = output.replacingOccurrences(of: "{{.CreatedAt}}", with: c.createdAgo)
                output = output.replacingOccurrences(of: "{{.Status}}", with: c.status)
                output = output.replacingOccurrences(of: "{{.Ports}}", with: c.ports.map(\.description).joined(separator: ", "))
                output = output.replacingOccurrences(of: "{{.Names}}", with: c.name)
                output = output.replacingOccurrences(of: "{{.State}}", with: c.state.displayString)
                output = output.replacingOccurrences(of: "{{.Labels}}", with: c.labels.map { "\($0.key)=\($0.value)" }.joined(separator: ","))
                print(output)
            }
            return
        }

        let headers = ["Container ID", "Image", "Command", "Created", "Status", "Ports", "Names"]
        let rows = containers.map { c in
            [
                noTrunc ? c.id : c.shortID,
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
