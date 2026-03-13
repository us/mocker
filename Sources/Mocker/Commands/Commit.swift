import ArgumentParser
import MockerKit

struct Commit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new image from a container's changes"
    )

    @Argument(help: "Container name or ID")
    var container: String

    @Argument(help: "Repository and tag (e.g. myimage:latest)")
    var repository: String?

    @Option(name: .shortAndLong, help: "Author (e.g., \"John Hannibal Smith <hannibal@a-team.com>\")")
    var author: String?

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Apply Dockerfile instruction to the created image")
    var change: [String] = []

    @Option(name: .shortAndLong, help: "Commit message")
    var message: String?

    @Flag(name: .customLong("no-pause"), help: "Disable pausing container during commit")
    var noPause = false

    func run() async throws {
        throw MockerError.operationFailed("commit is not yet supported with Apple Containerization")
    }
}
