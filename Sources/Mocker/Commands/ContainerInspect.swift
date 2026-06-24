import ArgumentParser
import MockerKit

struct ContainerInspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Display detailed information on one or more containers"
    )

    @Argument(help: "Container name or ID")
    var containers: [String]

    @Option(name: .shortAndLong, help: "Format output using a custom template")
    var format: String?

    @Flag(name: .shortAndLong, help: "Display total file sizes")
    var size = false  // --size accepted for Docker compatibility but no-op; wire up when ContainerEngine surfaces size data (PR 2)

    func run() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()
        let engine = try ContainerEngine(config: config)
        let results = try await inspectContainers(targets: containers, engine: engine)
        for container in results {
            try TableFormatter.printJSONArray(container)
        }
    }
}
