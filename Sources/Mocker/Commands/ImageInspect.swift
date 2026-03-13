import ArgumentParser
import MockerKit
import Foundation

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

    func run() async throws {
        let config = MockerConfig()
        let manager = try ImageManager(config: config)

        for image in images {
            let info = try await manager.inspect(image)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(info)
            print(String(data: data, encoding: .utf8) ?? "")
        }
    }
}
