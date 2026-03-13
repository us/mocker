import ArgumentParser
import MockerKit

struct ContainerPrune: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "Remove all stopped containers"
    )

    @Option(name: .long, parsing: .singleValue, help: "Provide filter values (e.g. \"until=<timestamp>\")")
    var filter: [String] = []

    @Flag(name: .shortAndLong, help: "Do not prompt for confirmation")
    var force = false

    func run() async throws {
        throw MockerError.operationFailed("container prune is not yet supported with Apple Containerization")
    }
}
