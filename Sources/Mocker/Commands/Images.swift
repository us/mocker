import ArgumentParser

struct Images: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "images",
        abstract: "List images"
    )

    @OptionGroup var options: ImageListOptions

    func run() async throws {
        try await options.render()
    }
}
