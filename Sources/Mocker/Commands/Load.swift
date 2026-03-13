import ArgumentParser
import MockerKit

struct Load: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Load an image from a tar archive or STDIN"
    )

    @Option(name: .shortAndLong, help: "Read from tar archive file, instead of STDIN")
    var input: String?

    @Flag(name: .shortAndLong, help: "Suppress the load output")
    var quiet = false

    @Option(name: .long, help: "Set platform to load for")
    var platform: String?

    func run() async throws {
        let config = MockerConfig()
        let manager = try ImageManager(config: config)

        guard let inputPath = input else {
            throw MockerError.operationFailed("input file required (use -i)")
        }

        let images = try await manager.load(from: inputPath)
        if !quiet {
            for image in images {
                print("Loaded image: \(image.repository):\(image.tag)")
            }
        }
    }
}
