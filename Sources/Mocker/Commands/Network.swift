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
            NetworkPrune.self,
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

    @Flag(name: .long, help: "Enable manual container attachment")
    var attachable = false

    @Option(name: .customLong("aux-address"), parsing: .singleValue, help: "Auxiliary IPv4 or IPv6 addresses used by Network driver")
    var auxAddress: [String] = []

    @Option(name: .customLong("config-from"), help: "The network from which to copy the configuration")
    var configFrom: String?

    @Flag(name: .customLong("config-only"), help: "Create a configuration only network")
    var configOnly = false

    @Flag(name: .long, help: "Create swarm routing-mesh network")
    var ingress = false

    @Flag(name: .long, help: "Restrict external access to the network")
    var `internal` = false

    @Option(name: .customLong("ip-range"), parsing: .singleValue, help: "Allocate container ip from a sub-range")
    var ipRange: [String] = []

    @Option(name: .customLong("ipam-driver"), help: "IP Address Management Driver")
    var ipamDriver: String?

    @Option(name: .customLong("ipam-opt"), parsing: .singleValue, help: "Set IPAM driver specific options")
    var ipamOpt: [String] = []

    @Flag(name: .long, help: "Enable or disable IPv4")
    var ipv4 = false

    @Flag(name: .long, help: "Enable or disable IPv6")
    var ipv6 = false

    @Option(name: .long, parsing: .singleValue, help: "Set metadata on a network")
    var label: [String] = []

    @Option(name: [.customShort("o"), .long], parsing: .singleValue, help: "Set driver specific options")
    var opt: [String] = []

    @Option(name: .long, help: "Control the network's scope")
    var scope: String?

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

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Filter output based on conditions provided")
    var filter: [String] = []

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    @Flag(name: .shortAndLong, help: "Only display network IDs")
    var quiet = false

    @Flag(name: .customLong("no-trunc"), help: "Don't truncate output")
    var noTrunc = false

    func run() async throws {
        let config = MockerConfig()
        let manager = try NetworkManager(config: config)
        var networks = await manager.list()

        for f in filter {
            let parts = f.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]), value = String(parts[1])
            switch key {
            case "name": networks = networks.filter { $0.name.contains(value) }
            case "driver": networks = networks.filter { $0.driver == value }
            case "id": networks = networks.filter { $0.id.hasPrefix(value) }
            default: break
            }
        }

        if quiet {
            for n in networks { print(noTrunc ? n.id : n.shortID) }
            return
        }

        if let format {
            for n in networks {
                var output = format
                output = output.replacingOccurrences(of: "{{.ID}}", with: noTrunc ? n.id : n.shortID)
                output = output.replacingOccurrences(of: "{{.Name}}", with: n.name)
                output = output.replacingOccurrences(of: "{{.Driver}}", with: n.driver)
                output = output.replacingOccurrences(of: "{{.Scope}}", with: "local")
                print(output)
            }
            return
        }

        let headers = ["Network ID", "Name", "Driver", "Scope"]
        let rows = networks.map { n in
            [noTrunc ? n.id : n.shortID, n.name, n.driver, "local"]
        }
        TableFormatter.print(headers: headers, rows: rows)
    }
}

struct NetworkRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove one or more networks"
    )

    @Flag(name: .shortAndLong, help: "Do not error if the network does not exist")
    var force = false

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

    @Option(name: .shortAndLong, help: "Format output using the given Go template")
    var format: String?

    @Flag(name: .shortAndLong, help: "Verbose output for diagnostics")
    var verbose = false

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

    @Option(name: .long, parsing: .singleValue, help: "Add network-scoped alias for the container")
    var alias: [String] = []

    @Option(name: .customLong("driver-opt"), parsing: .singleValue, help: "Driver options for the network")
    var driverOpt: [String] = []

    @Option(name: .customLong("gw-priority"), help: "Gateway priority for the container")
    var gwPriority: Int?

    @Option(name: .long, help: "IPv4 address")
    var ip: String?

    @Option(name: .long, help: "IPv6 address")
    var ip6: String?

    @Option(name: .long, parsing: .singleValue, help: "Add link to another container")
    var link: [String] = []

    @Option(name: .customLong("link-local-ip"), parsing: .singleValue, help: "Add a link-local address for the container")
    var linkLocalIp: [String] = []

    func run() async throws {
        let config = MockerConfig()
        let manager = try NetworkManager(config: config)
        try await manager.connect(container: container, network: network)
    }
}

struct NetworkPrune: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "Remove all unused networks"
    )

    @Flag(name: .shortAndLong, help: "Do not prompt for confirmation")
    var force = false

    @Option(name: .long, parsing: .singleValue, help: "Provide filter values")
    var filter: [String] = []

    func run() async throws {
        if !force {
            print("WARNING! This will remove all custom networks not used by at least one container.")
            print("Are you sure you want to continue? [y/N] ", terminator: "")
            guard let answer = readLine(), answer.lowercased() == "y" else {
                print("Cancelled.")
                return
            }
        }

        let config = MockerConfig()
        let manager = try NetworkManager(config: config)
        let networks = await manager.list()

        var removed = 0
        for n in networks where n.name != "bridge" && n.name != "host" && n.name != "none" {
            _ = try? await manager.remove(n.name)
            removed += 1
        }
        print("Deleted \(removed) networks")
    }
}

struct NetworkDisconnect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disconnect",
        abstract: "Disconnect a container from a network"
    )

    @Flag(name: .shortAndLong, help: "Force the container to disconnect from a network")
    var force = false

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
