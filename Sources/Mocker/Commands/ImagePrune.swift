import ArgumentParser
import MockerKit

struct ImagePrune: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "Remove unused images"
    )

    @Flag(name: .shortAndLong, help: "Remove all unused images, not just dangling ones")
    var all = false

    @Option(name: .long, parsing: .singleValue, help: "Provide filter values (e.g. \"until=<timestamp>\")")
    var filter: [String] = []

    @Flag(name: .shortAndLong, help: "Do not prompt for confirmation")
    var force = false

    func run() async throws {
        throw MockerError.operationFailed("image prune is not yet supported with Apple Containerization")
    }
}
