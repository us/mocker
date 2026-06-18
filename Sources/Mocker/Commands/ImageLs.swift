import ArgumentParser
import MockerKit

struct Images: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List images"
    )

    @Flag(name: .shortAndLong, help: "Only show image IDs")
    var quiet = false

    @Flag(name: .shortAndLong, help: "Show all images (default hides intermediate images)")
    var all = false

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Filter output based on conditions provided")
    var filter: [String] = []

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    @Flag(name: .long, help: "Show digests")
    var digests = false

    @Flag(name: .customLong("no-trunc"), help: "Don't truncate output")
    var noTrunc = false

    @Flag(name: .long, help: "List images in tree format (experimental)")
    var tree = false

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
