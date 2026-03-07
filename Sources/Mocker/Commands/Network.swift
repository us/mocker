import ArgumentParser
import MockerKit

struct NetworkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "network",
        abstract: "Manage networks",
        subcommands: [
            NetworkCreate.self,
            NetworkList.self,
            NetworkRemove.self,
            NetworkInspect.self,
            NetworkConnect.self,
            NetworkDisconnect.self,
        ]
    )
}

struct NetworkCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a network"
    )

    @Argument(help: "Network name")
    var name: String

    @Option(name: .shortAndLong, help: "Driver to manage the network")
    var driver: String = "bridge"

    @Option(name: .long, help: "Subnet in CIDR format")
    var subnet: String?

    @Option(name: .long, help: "Gateway for the subnet")
    var gateway: String?

    func run() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()
        let manager = try NetworkManager(config: config)
        let network = try await manager.create(name: name, driver: driver, subnet: subnet, gateway: gateway)
        print(network.id)
    }
}

struct NetworkList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List networks"
    )

    func run() async throws {
        let config = MockerConfig()
        let manager = try NetworkManager(config: config)
        let networks = await manager.list()

        let headers = ["Network ID", "Name", "Driver", "Scope"]
        let rows = networks.map { n in
            [n.shortID, n.name, n.driver, "local"]
        }
        TableFormatter.print(headers: headers, rows: rows)
    }
}

struct NetworkRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove one or more networks"
    )

    @Argument(help: "Network names")
    var networks: [String]

    func run() async throws {
        let config = MockerConfig()
        let manager = try NetworkManager(config: config)
        for name in networks {
            let network = try await manager.remove(name)
            print(network.name)
        }
    }
}

struct NetworkInspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Display detailed information on a network"
    )

    @Argument(help: "Network name")
    var name: String

    func run() async throws {
        let config = MockerConfig()
        let manager = try NetworkManager(config: config)
        let network = try await manager.inspect(name)
        try TableFormatter.printJSON(network)
    }
}

struct NetworkConnect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect",
        abstract: "Connect a container to a network"
    )

    @Argument(help: "Network name")
    var network: String

    @Argument(help: "Container name or ID")
    var container: String

    func run() async throws {
        let config = MockerConfig()
        let manager = try NetworkManager(config: config)
        try await manager.connect(container: container, network: network)
    }
}

struct NetworkDisconnect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disconnect",
        abstract: "Disconnect a container from a network"
    )

    @Argument(help: "Network name")
    var network: String

    @Argument(help: "Container name or ID")
    var container: String

    func run() async throws {
        let config = MockerConfig()
        let manager = try NetworkManager(config: config)
        try await manager.disconnect(container: container, network: network)
    }
}
