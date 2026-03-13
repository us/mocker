import ArgumentParser
import MockerKit

struct Save: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Save one or more images to a tar archive"
    )

    @Argument(help: "Image references to save")
    var images: [String]

    @Option(name: .shortAndLong, help: "Write to a file, instead of STDOUT")
    var output: String?

    @Option(name: .long, help: "Set platform to save for")
    var platform: String?

    func run() async throws {
        let config = MockerConfig()
        let manager = try ImageManager(config: config)

        guard let outputPath = output else {
            throw MockerError.operationFailed("output file required (use -o)")
        }

        try await manager.save(references: images, to: outputPath)
        print("Saved \(images.count) image(s) to \(outputPath)")
    }
}
