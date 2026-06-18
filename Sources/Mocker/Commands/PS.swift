import ArgumentParser

struct PS: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ps",
        abstract: "List containers"
    )

    @OptionGroup var options: ContainerListOptions

    func run() async throws {
        try await options.render()
    }
}
