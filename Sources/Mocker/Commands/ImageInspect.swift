import ArgumentParser
import MockerKit

struct ImageInspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Display detailed information on one or more images"
    )

    @Argument(help: "Image name or ID")
    var images: [String]

    @Option(name: .shortAndLong, help: "Format output using a custom template")
    var format: String?

    @Option(name: .long, help: "Inspect a specific platform of the multi-platform image")
    var platform: String?

    // MARK: - Run

    func run() async throws {
        let manager = try ImageManager(config: MockerConfig())
        var results: [MockerKit.ImageInspect] = []
        for image in images {
            let info = try await manager.inspect(image, platform: platform)
            results.append(info)
        }
        try TableFormatter.printJSONArray(results, escapeSlashes: false)
    }
}
