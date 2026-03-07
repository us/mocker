import ArgumentParser
import Foundation
import MockerKit

struct SystemCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "system",
        abstract: "Manage Mocker system",
        subcommands: [
            SystemInfo.self,
            SystemPrune.self,
        ]
    )
}

struct SystemInfo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Display system-wide information"
    )

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        let imageManager = try ImageManager(config: config)

        let containers = try await engine.list(all: true)
        let running = containers.filter { $0.state == .running }.count
        let paused = containers.filter { $0.state == .paused }.count
        let stopped = containers.count - running - paused
        let images = try await imageManager.list()

        let info = ProcessInfo.processInfo

        print("Client:")
        print(" Version:    0.1.0")
        print(" Context:    default")
        print("")
        print("Server:")
        print(" Containers: \(containers.count)")
        print("  Running:   \(running)")
        print("  Paused:    \(paused)")
        print("  Stopped:   \(stopped)")
        print(" Images:     \(images.count)")
        print(" Server Version: 0.1.0")
        print(" Storage Driver: json-file")
        print(" Operating System: macOS \(info.operatingSystemVersionString)")
        print(" Architecture: \(architectureString())")
        print(" CPUs: \(ProcessInfo.processInfo.processorCount)")
        print(" Total Memory: \(formatMemory(ProcessInfo.processInfo.physicalMemory))")
        print(" Docker Root Dir: \(config.dataRoot)")
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824.0
        return String(format: "%.2fGiB", gib)
    }

    private func architectureString() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

struct SystemPrune: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "Remove unused data"
    )

    @Flag(name: .shortAndLong, help: "Remove all unused images, not just dangling ones")
    var all = false

    @Flag(name: .long, help: "Also prune volumes")
    var volumes = false

    @Flag(name: .shortAndLong, help: "Do not prompt for confirmation")
    var force = false

    func run() async throws {
        if !force {
            print("WARNING! This will remove:")
            print("  - all stopped containers")
            if all {
                print("  - all unused images")
            } else {
                print("  - all dangling images")
            }
            if volumes {
                print("  - all unused volumes")
            }
            print("")
            print("Are you sure you want to continue? [y/N] ", terminator: "")

            guard let answer = readLine(), answer.lowercased() == "y" else {
                print("Cancelled.")
                return
            }
        }

        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        // Remove stopped containers
        let containers = try await engine.list(all: true)
        var removedContainers = 0
        for container in containers where !container.state.isActive {
            _ = try await engine.remove(container.id)
            removedContainers += 1
        }

        print("Deleted \(removedContainers) containers")
        print("Total reclaimed space: 0B") // TODO: Calculate actual space
    }
}
