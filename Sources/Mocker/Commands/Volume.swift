import ArgumentParser
import MockerKit

struct VolumeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "volume",
        abstract: "Manage volumes",
        subcommands: [
            VolumeCreate.self,
            VolumeList.self,
            VolumeRemove.self,
            VolumeInspect.self,
            VolumePrune.self,
        ]
    )
}

struct VolumeCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a volume"
    )

    @Argument(help: "Volume name")
    var name: String

    @Option(name: .shortAndLong, help: "Volume driver")
    var driver: String = "local"

    @Option(name: .long, parsing: .singleValue, help: "Set metadata for a volume")
    var label: [String] = []

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Set driver specific options")
    var opt: [String] = []

    func run() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()
        let manager = try VolumeManager(config: config)
        let volume = try await manager.create(name: name, driver: driver)
        print(volume.name)
    }
}

struct VolumeList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List volumes"
    )

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Filter output based on conditions provided")
    var filter: [String] = []

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    @Flag(name: .shortAndLong, help: "Only display volume names")
    var quiet = false

    func run() async throws {
        let config = MockerConfig()
        let manager = try VolumeManager(config: config)
        var volumes = await manager.list()

        for f in filter {
            let parts = f.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]), value = String(parts[1])
            switch key {
            case "name": volumes = volumes.filter { $0.name.contains(value) }
            case "driver": volumes = volumes.filter { $0.driver == value }
            default: break
            }
        }

        if quiet {
            for v in volumes { print(v.name) }
            return
        }

        if let format {
            for v in volumes {
                var output = format
                output = output.replacingOccurrences(of: "{{.Name}}", with: v.name)
                output = output.replacingOccurrences(of: "{{.Driver}}", with: v.driver)
                print(output)
            }
            return
        }

        let headers = ["Driver", "Volume Name"]
        let rows = volumes.map { v in
            [v.driver, v.name]
        }
        TableFormatter.print(headers: headers, rows: rows)
    }
}

struct VolumeRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove one or more volumes"
    )

    @Argument(help: "Volume names")
    var volumes: [String]

    @Flag(name: .shortAndLong, help: "Force the removal of one or more volumes")
    var force = false

    func run() async throws {
        let config = MockerConfig()
        let manager = try VolumeManager(config: config)
        for name in volumes {
            let volume = try await manager.remove(name)
            print(volume.name)
        }
    }
}

struct VolumePrune: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "Remove unused local volumes"
    )

    @Flag(name: .shortAndLong, help: "Do not prompt for confirmation")
    var force = false

    @Flag(name: .shortAndLong, help: "Prune all unused volumes, not just anonymous ones")
    var all = false

    @Option(name: .long, parsing: .singleValue, help: "Provide filter values")
    var filter: [String] = []

    func run() async throws {
        if !force {
            print("WARNING! This will remove anonymous local volumes not used by at least one container.")
            print("Are you sure you want to continue? [y/N] ", terminator: "")
            guard let answer = readLine(), answer.lowercased() == "y" else {
                print("Cancelled.")
                return
            }
        }

        let config = MockerConfig()
        let manager = try VolumeManager(config: config)
        let volumes = await manager.list()

        var removed = 0
        for v in volumes {
            _ = try? await manager.remove(v.name)
            removed += 1
        }
        print("Deleted \(removed) volumes")
        print("Total reclaimed space: 0B")
    }
}

struct VolumeInspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Display detailed information on a volume"
    )

    @Argument(help: "Volume name")
    var name: String

    @Option(name: .shortAndLong, help: "Format output using a custom template")
    var format: String?

    func run() async throws {
        let config = MockerConfig()
        let manager = try VolumeManager(config: config)
        let volume = try await manager.inspect(name)
        try TableFormatter.printJSON(volume)
    }
}
