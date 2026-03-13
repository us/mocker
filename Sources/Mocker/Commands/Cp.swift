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
        let (srcContainer, srcPath) = parseCpArg(source)
        let (dstContainer, dstPath) = parseCpArg(destination)

        if let containerName = srcContainer {
            // Copy from container to host
            let data = try await engine.copyFromContainer(containerName, path: srcPath)
            try data.write(to: URL(fileURLWithPath: dstPath))
        } else if let containerName = dstContainer {
            // Copy from host to container
            let data = try Data(contentsOf: URL(fileURLWithPath: srcPath))
            try await engine.copyToContainer(containerName, path: dstPath, data: data)
        } else {
            throw MockerError.operationFailed("copying requires one of source or destination to be a container")
        }
    }

    private func parseCpArg(_ arg: String) -> (String?, String) {
        // Format: "container:path" or just "path"
        let parts = arg.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2 && !parts[0].hasPrefix("/") && !parts[0].hasPrefix(".") {
            return (parts[0], parts[1])
        }
        return (nil, arg)
    }
}
