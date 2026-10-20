import ArgumentParser
import MockerKit
import Foundation

struct Cp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Copy files/folders between a container and the local filesystem"
    )

    @Argument(help: "Source path (container:path or local path)")
    var source: String

    @Argument(help: "Destination path (container:path or local path)")
    var destination: String

    @Flag(name: .shortAndLong, help: "Archive mode (copy all uid/gid information)")
    var archive = false

    @Flag(name: [.customShort("L"), .customLong("follow-link")], help: "Always follow symbol link in SRC_PATH")
    var followLink = false

    @Flag(name: .shortAndLong, help: "Suppress progress output during copy")
    var quiet = false

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        // Parse source and destination: "container:path" or just "path"
        let (srcContainer, srcPath) = Self.parseCpArg(source)
        let (dstContainer, dstPath) = Self.parseCpArg(destination)

        switch (srcContainer, dstContainer) {
        case (nil, nil):
            throw MockerError.operationFailed("copying requires one of source or destination to be a container")
        case (.some, .some):
            throw MockerError.operationFailed("copying between containers is not supported")
        default:
            break
        }

        // `container cp` wants the runtime's container name; resolve Docker names,
        // IDs and prefixes to it the same way every other command does.
        let src = try await resolved(srcContainer, srcPath, engine)
        let dst = try await resolved(dstContainer, dstPath, engine)
        try await engine.copy(from: src, to: dst)
    }

    private func resolved(_ container: String?, _ path: String, _ engine: ContainerEngine) async throws -> String {
        guard let container else { return path }
        return "\(try await engine.inspect(container).name):\(path)"
    }

    /// Split `container:path` from a plain host path. Pure; safe to unit-test.
    static func parseCpArg(_ arg: String) -> (String?, String) {
        // Format: "container:path" or just "path"
        let parts = arg.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2 && !parts[0].hasPrefix("/") && !parts[0].hasPrefix(".") {
            return (parts[0], parts[1])
        }
        return (nil, arg)
    }
}
