import ArgumentParser
import Foundation
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
        // Pruning more than the filter asks for would delete images the user meant to keep.
        guard filter.isEmpty else {
            throw MockerError.operationFailed("image prune --filter is not supported")
        }
        if !force {
            print("WARNING! This will remove \(all ? "all images without at least one container associated to them" : "all dangling images").")
            print("Are you sure you want to continue? [y/N] ", terminator: "")
            guard let answer = readLine(), answer.lowercased() == "y" else {
                print("Cancelled.")
                return
            }
        }

        let config = MockerConfig()
        let inUse = try await ContainerEngine(config: config).imagesInUse()
        let result = try await ImageManager(config: config).prune(all: all, inUse: inUse)
        Self.report(result.removed)
        print("Total reclaimed space: \(Self.bytes(result.reclaimed))")
    }

    /// Docker's listing of what went: one `untagged:` line per name.
    static func report(_ images: [ImageInfo]) {
        guard !images.isEmpty else { return }
        print("Deleted Images:")
        for image in images { print("untagged: \(image.reference)") }
        print("")
    }

    static func bytes(_ count: UInt64) -> String {
        // The formatter says "Zero KB"; Docker says "0B".
        count == 0 ? "0B" : ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
