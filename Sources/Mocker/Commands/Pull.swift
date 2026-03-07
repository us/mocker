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

        if !image.contains(":") {
            print("Using default tag: latest")
        }

        let (info, alreadyExists) = try await manager.pull(image)

        if alreadyExists {
            print("Digest: \(info.id)")
            print("Status: Image is up to date for \(ref.fullReference)")
            print(ref.fullReference)
            return
        }

        print("\(ref.tag): Pulling from \(ref.fullRepository)")
        print("Digest: \(info.id)")
        print("Status: Downloaded newer image for \(ref.fullReference)")
        print(ref.fullReference)
    }
}
