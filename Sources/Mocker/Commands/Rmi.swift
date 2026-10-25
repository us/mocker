import ArgumentParser
import MockerKit

struct Rmi: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rmi",
        abstract: "Remove one or more images"
    )

    @Argument(help: "Image reference(s) to remove")
    var images: [String]

    @Flag(name: .shortAndLong, help: "Force removal of the image")
    var force = false

    @Flag(name: .customLong("no-prune"), help: "Do not delete untagged parents")
    var noPrune = false

    @Option(name: .long, parsing: .singleValue, help: "Remove only the given platform variant")
    var platform: [String] = []

    func run() async throws {
        let config = MockerConfig()
        let manager = try ImageManager(config: config)

        for reference in images {
            let removal = try await manager.remove(reference, force: force)
            for image in removal.untagged {
                print("Untagged: \(image.reference)")
            }
            if removal.deleted, let image = removal.untagged.first {
                print("Deleted: \(image.id)")
            }
        }
    }
}
