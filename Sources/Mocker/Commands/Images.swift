import ArgumentParser
import MockerKit

struct Images: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List images"
    )

    @Flag(name: .shortAndLong, help: "Only show image IDs")
    var quiet = false

    func run() async throws {
        let config = MockerConfig()
        let manager = try ImageManager(config: config)
        let images = try await manager.list()

        if quiet {
            for image in images {
                print(image.shortID)
            }
            return
        }

        let headers = ["Repository", "Tag", "Image ID", "Created", "Size"]
        let rows = images.map { img in
            [
                img.repository,
                img.tag,
                img.shortID,
                img.createdAgo,
                img.sizeString,
            ]
        }
        TableFormatter.print(headers: headers, rows: rows)
    }
}
