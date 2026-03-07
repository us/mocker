import ArgumentParser
import MockerKit

struct Tag: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a tag that refers to a source image"
    )

    @Argument(help: "Source image reference")
    var source: String

    @Argument(help: "Target image reference")
    var target: String

    func run() async throws {
        let config = MockerConfig()
        let manager = try ImageManager(config: config)
        try await manager.tag(source, target)
    }
}
