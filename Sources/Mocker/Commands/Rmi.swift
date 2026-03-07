import ArgumentParser
import MockerKit

struct Rmi: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rmi",
        abstract: "Remove one or more images"
    )

    @Argument(help: "Image reference(s) to remove")
    var images: [String]

    @Flag(name: .shortAndLong, help: "Force removal")
    var force = false

    func run() async throws {
        let config = MockerConfig()
        let manager = try ImageManager(config: config)

        for reference in images {
            let image = try await manager.remove(reference)
            print("Untagged: \(image.reference)")
            print("Deleted: \(image.id)")
        }
    }
}
