import ArgumentParser
import MockerKit

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build an image from a Dockerfile"
    )

    @Argument(help: "Build context path")
    var context: String = "."

    @Option(name: .shortAndLong, help: "Name and optionally a tag (name:tag)")
    var tag: String

    @Option(name: .shortAndLong, help: "Name of the Dockerfile")
    var file: String = "Dockerfile"

    @Flag(name: .long, help: "Do not use cache when building")
    var noCache = false

    func run() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()
        let manager = try ImageManager(config: config)

        print("Building \(tag)...")
        let image = try await manager.build(tag: tag, context: context, dockerfile: file)
        print("Successfully built \(image.shortID)")
        print("Successfully tagged \(tag)")
    }
}
