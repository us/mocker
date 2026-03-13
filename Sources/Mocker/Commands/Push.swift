import ArgumentParser
import MockerKit

struct Push: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Upload an image to a registry"
    )

    @Argument(help: "Image reference to push")
    var image: String

    @Flag(name: .shortAndLong, help: "Push all tags of an image to the repository")
    var allTags = false

    @Option(name: .long, help: "Push a platform-specific manifest")
    var platform: String?

    @Flag(name: .shortAndLong, help: "Suppress verbose output")
    var quiet = false

    func run() async throws {
        let config = MockerConfig()
        let manager = try ImageManager(config: config)

        let ref = try ImageReference.parse(image)
        print("Pushing \(ref.fullReference)...")
        try await manager.push(image)
        print("Successfully pushed \(ref.fullReference)")
    }
}
