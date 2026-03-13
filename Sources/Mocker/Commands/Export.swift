import ArgumentParser
import MockerKit

struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Export a container's filesystem as a tar archive"
    )

    @Argument(help: "Container name or ID")
    var container: String

    @Option(name: .shortAndLong, help: "Write to a file, instead of STDOUT")
    var output: String?

    func run() async throws {
        // Export is a best-effort implementation
        throw MockerError.operationFailed("export is not yet supported with Apple Containerization")
    }
}

struct Import: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import the contents from a tarball to create a filesystem image"
    )

    @Argument(help: "File or URL to import")
    var source: String

    @Argument(help: "Repository and tag (e.g. myimage:latest)")
    var repository: String?

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Apply Dockerfile instruction to the created image")
    var change: [String] = []

    @Option(name: .shortAndLong, help: "Set commit message for imported image")
    var message: String?

    @Option(name: .long, help: "Set platform for imported image")
    var platform: String?

    func run() async throws {
        throw MockerError.operationFailed("import is not yet supported with Apple Containerization")
    }
}
