import ArgumentParser
import MockerKit

struct Inspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Return low-level information on container or image"
    )

    @Argument(help: "Container or image name/ID")
    var targets: [String]

    @Option(name: .shortAndLong, help: "Format output using a custom template")
    var format: String?

    @Option(name: .long, help: "Only inspect objects of the given type")
    var type: String?

    @Flag(name: .shortAndLong, help: "Display total file sizes if the type is container")
    var size = false

    func run() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()

        let engine = try ContainerEngine(config: config)
        let imageManager = try ImageManager(config: config)

        for target in targets {
            // Try container first, then image
            if let container = try? await engine.inspect(target) {
                try TableFormatter.printJSONArray(container)
            } else if let image = try? await imageManager.inspect(target) {
                try TableFormatter.printJSONArray(image)
            } else {
                throw MockerError.containerNotFound(target)
            }
        }
    }
}
