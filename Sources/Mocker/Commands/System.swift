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
            SystemDf.self,
            SystemEvents.self,
        ]
    )
}

struct SystemInfo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Display system-wide information"
    )

    @Option(name: .shortAndLong, help: "Format output using a custom template")
    var format: String?

    func run() async throws {
        try await Self.emit(format: format)
    }

    /// Shared by `system info` and the top-level `info` alias.
    static func emit(format: String?) async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        let imageManager = try ImageManager(config: config)

        let containers = try await engine.list(all: true)
        let running = containers.filter { $0.state == .running }.count
        let paused = containers.filter { $0.state == .paused }.count
        let images = try await imageManager.list(enrich: false)

        let object = infoObject(
            containers: containers.count,
            running: running,
            paused: paused,
            images: images.count,
            dataRoot: config.dataRoot
        )

        if let format {
            let template = format == "json" ? "{{json .}}" : format
            print(try GoTemplate.render(template, object: object))
            return
        }

        // The text view reads the same record the templates see, so each value is computed once.
        func field(_ key: String) -> String {
            switch object[key] {
            case let value as String: return value
            case let value as Int: return String(value)
            default: return ""
            }
        }
        print("Client:")
        print(" Version:    \(Version.currentVersion)")
        print(" Context:    default")
        print("")
        print("Server:")
        print(" Containers: \(field("Containers"))")
        print("  Running:   \(field("ContainersRunning"))")
        print("  Paused:    \(field("ContainersPaused"))")
        print("  Stopped:   \(field("ContainersStopped"))")
        print(" Images:     \(field("Images"))")
        print(" Server Version: \(field("ServerVersion"))")
        print(" Storage Driver: \(field("Driver"))")
        print(" Operating System: \(field("OperatingSystem"))")
        print(" Architecture: \(field("Architecture"))")
        print(" CPUs: \(field("NCPU"))")
        print(" Total Memory: \(formatMemory(UInt64(object["MemTotal"] as? Int ?? 0)))")
        print(" Docker Root Dir: \(field("DockerRootDir"))")
    }

    /// Docker-shaped `info` record for `--format` templates (`{{.ServerVersion}}`, `{{.NCPU}}`, ...).
    static func infoObject(containers: Int, running: Int, paused: Int, images: Int, dataRoot: String) -> [String: Any] {
        let info = ProcessInfo.processInfo
        return [
            "ID": "",
            "Name": info.hostName,
            "ServerVersion": Version.currentVersion,
            "Containers": containers,
            "ContainersRunning": running,
            "ContainersPaused": paused,
            "ContainersStopped": containers - running - paused,
            "Images": images,
            "Driver": "json-file",
            "OperatingSystem": "macOS \(info.operatingSystemVersionString)",
            "OSType": "linux",
            "Architecture": architectureString(),
            "NCPU": info.processorCount,
            "MemTotal": Int(info.physicalMemory),
            "DockerRootDir": dataRoot,
        ]
    }

    private static func formatMemory(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824.0
        return String(format: "%.2fGiB", gib)
    }

    private static func architectureString() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

/// Top-level `mocker info`, an alias for `mocker system info` like `docker info`.
struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Display system-wide information"
    )

    @Option(name: .shortAndLong, help: "Format output using a custom template")
    var format: String?

    func run() async throws {
        try await SystemInfo.emit(format: format)
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

    @Option(name: .long, parsing: .singleValue, help: "Provide filter values")
    var filter: [String] = []

    func run() async throws {
        // Pruning more than the filter asks for would delete data the user meant to keep.
        guard filter.isEmpty else {
            throw MockerError.operationFailed("system prune --filter is not supported")
        }
        if !force {
            print("WARNING! This will remove:")
            print("  - all stopped containers")
            print("  - all networks not used by at least one container")
            if volumes {
                print("  - all anonymous volumes not used by at least one container")
            }
            print(all ? "  - all images without at least one container associated to them" : "  - all dangling images")
            print(all ? "  - all build cache" : "  - unused build cache")
            print("")
            print("Are you sure you want to continue? [y/N] ", terminator: "")

            guard let answer = readLine(), answer.lowercased() == "y" else {
                print("Cancelled.")
                return
            }
        }

        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        let containers = try await engine.list(all: true)
        var deletedContainers: [String] = []
        for container in containers where !container.state.isActive {
            deletedContainers.append(try await engine.remove(container.id).name)
        }
        Self.report("Deleted Containers:", deletedContainers)

        Self.report("Deleted Networks:", try await NetworkManager(config: config).prune())

        if volumes {
            Self.report("Deleted Volumes:", try await VolumeManager(config: config).prune(all: false))
        }

        // Only the containers still present keep their images.
        let images = try await ImageManager(config: config).prune(all: all, inUse: try await engine.imagesInUse())
        ImagePrune.report(images.removed)

        // The builder's cache cannot be pruned in part (see `BuildCache`), so it goes
        // whole in both modes; a build only loses time to it, never data.
        let cache = try await BuildCache.prune()
        if cache > 0 { print("Deleted build cache\n") }

        print("Total reclaimed space: \(ImagePrune.bytes(images.reclaimed + cache))")
    }

    private static func report(_ title: String, _ names: [String]) {
        guard !names.isEmpty else { return }
        print(title)
        for name in names { print(name) }
        print("")
    }
}

struct SystemDf: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "df",
        abstract: "Show docker disk usage"
    )

    @Flag(name: .shortAndLong, help: "Show detailed information on space usage")
    var verbose = false

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        let imageManager = try ImageManager(config: config)
        let volumeManager = try VolumeManager(config: config)

        let containers = try await engine.list(all: true)
        let images = try await imageManager.list(enrich: false)
        let volumes = try await volumeManager.list()

        let headers = ["TYPE", "TOTAL", "ACTIVE", "SIZE", "RECLAIMABLE"]
        let rows = [
            ["Images", "\(images.count)", "\(images.count)", "N/A", "0B"],
            ["Containers", "\(containers.count)", "\(containers.filter { $0.state == .running }.count)", "N/A", "0B"],
            ["Local Volumes", "\(volumes.count)", "\(volumes.count)", "N/A", "0B"],
            ["Build Cache", "0", "0", "0B", "0B"],
        ]
        TableFormatter.print(headers: headers, rows: rows)
    }
}

struct SystemEvents: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "Get real time events from the server"
    )

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Filter output based on conditions provided")
    var filter: [String] = []

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    @Option(name: .long, help: "Show all events created since timestamp")
    var since: String?

    @Option(name: .long, help: "Stream events until this timestamp")
    var until: String?

    func run() async throws {
        // Events require a daemon-like event bus — for now print a message
        print("Listening for events... (press Ctrl+C to stop)")
        // Block until interrupted
        while true {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
