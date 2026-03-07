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

    func run() async throws {
        let config = MockerConfig()
        let manager = try VolumeManager(config: config)
        let volumes = await manager.list()

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

    func run() async throws {
        let config = MockerConfig()
        let manager = try VolumeManager(config: config)
        for name in volumes {
            let volume = try await manager.remove(name)
            print(volume.name)
        }
    }
}

struct VolumeInspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Display detailed information on a volume"
    )

    @Argument(help: "Volume name")
    var name: String

    func run() async throws {
        let config = MockerConfig()
        let manager = try VolumeManager(config: config)
        let volume = try await manager.inspect(name)
        try TableFormatter.printJSON(volume)
    }
}
