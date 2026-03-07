import ArgumentParser
import MockerKit

struct Push: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Upload an image to a registry"
    )

    @Argument(help: "Image reference to push")
    var image: String

    func run() async throws {
        let config = MockerConfig()
        let manager = try ImageManager(config: config)

        let ref = try ImageReference.parse(image)
        print("Pushing \(ref.fullReference)...")
        try await manager.push(image)
        print("Successfully pushed \(ref.fullReference)")
    }
}
