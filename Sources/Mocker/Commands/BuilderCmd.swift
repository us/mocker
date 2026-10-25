import ArgumentParser
import MockerKit

struct BuilderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "builder",
        abstract: "Manage builds",
        subcommands: [BuilderPrune.self]
    )
}

struct BuilderPrune: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "Remove build cache"
    )

    @Flag(name: .shortAndLong, help: "Remove all unused build cache, not just dangling ones")
    var all = false

    @Flag(name: .shortAndLong, help: "Do not prompt for confirmation")
    var force = false

    func run() async throws {
        // The cache cannot be pruned in part (see `BuildCache`), so --all changes nothing here.
        if !force {
            print("WARNING! This will remove all build cache. Are you sure you want to continue? [y/N] ", terminator: "")
            guard let answer = readLine(), answer.lowercased() == "y" else {
                print("Cancelled.")
                return
            }
        }
        print("Total: \(ImagePrune.bytes(try await BuildCache.prune()))")
    }
}
