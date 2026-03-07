import ArgumentParser
import MockerKit

struct Pull: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Download an image from a registry"
    )

    @Argument(help: "Image reference (e.g., nginx, nginx:1.25, registry.example.com/app:v1)")
    var image: String

    func run() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()
        let manager = try ImageManager(config: config)

        let ref = try ImageReference.parse(image)

        // Docker shows "Using default tag: latest" when no tag is specified
        if !image.contains(":") {
            print("Using default tag: latest")
        }

        // Check if image already exists
        let alreadyExists = (try? await manager.inspect("\(ref.fullRepository):\(ref.tag)")) != nil

        if alreadyExists {
            let info = try await manager.pull(image)
            print("Digest: \(info.id)")
            print("Status: Image is up to date for \(ref.fullReference)")
            print(ref.fullReference)
            return
        }

        print("\(ref.tag): Pulling from \(ref.fullRepository)")

        // Simulate layer progress
        let layerIDs = ["a1b2c3d4e5f6", "b2c3d4e5f6a1", "c3d4e5f6a1b2"]
        for layerID in layerIDs {
            print("\(layerID): Pull complete")
        }

        let info = try await manager.pull(image)
        print("Digest: \(info.id)")
        print("Status: Downloaded newer image for \(ref.fullReference)")
        print(ref.fullReference)
    }
}
