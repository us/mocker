import ArgumentParser
import MockerKit

struct History: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the history of an image"
    )

    @Argument(help: "Image name or ID")
    var image: String

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    @Flag(name: [.customShort("H"), .long], inversion: .prefixedNo, help: "Print sizes and dates in human readable format")
    var human = true

    @Flag(name: .customLong("no-trunc"), help: "Don't truncate output")
    var noTrunc = false

    @Flag(name: .shortAndLong, help: "Only show image IDs")
    var quiet = false

    @Option(name: .long, help: "Set platform to show history for")
    var platform: String?

    func run() async throws {
        let config = MockerConfig()
        let manager = try ImageManager(config: config)
        let info = try await manager.inspect(image)

        if quiet {
            print(noTrunc ? info.id : info.shortID)
            return
        }

        // Simplified history — show single layer since we don't have full layer info
        let headers = ["IMAGE", "CREATED", "CREATED BY", "SIZE", "COMMENT"]
        let rows = [[
            noTrunc ? info.id : info.shortID,
            info.createdAgo,
            "",
            info.sizeString,
            "",
        ]]
        TableFormatter.print(headers: headers, rows: rows)
    }
}
