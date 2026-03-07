import ArgumentParser
import Foundation
import MockerKit

struct ComposeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compose",
        abstract: "Manage multi-container applications",
        subcommands: [
            ComposeUp.self,
            ComposeDown.self,
            ComposePS.self,
            ComposeLogs.self,
            ComposeRestart.self,
        ]
    )
}

// MARK: - Shared Options

struct ComposeOptions: ParsableArguments {
    @Option(name: [.customShort("f"), .long], help: "Compose file path")
    var file: String = "docker-compose.yml"

    @Option(name: [.customShort("p"), .customLong("project-name")], help: "Project name")
    var projectName: String?

    func loadCompose() throws -> (ComposeFile, String) {
        let path = file
        let composeFile = try ComposeFile.load(from: path)

        // Derive project name from directory if not specified
        let project = projectName ?? URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .lastPathComponent
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")

        return (composeFile, project)
    }
}

// MARK: - Compose Event Formatting

enum ComposeFormatter {
    static func printEvents(_ events: [ComposeEvent], total: Int) {
        print("[+] Running \(events.count)/\(total)")
        for event in events {
            let (name, action) = describe(event)
            print(" \u{2714} \(name.padding(toLength: 40, withPad: " ", startingAt: 0)) \(action)")
        }
    }

    private static func describe(_ event: ComposeEvent) -> (String, String) {
        switch event {
        case .networkCreated(let name): ("Network \(name)", "Created")
        case .volumeCreated(let name): ("Volume \(name)", "Created")
        case .containerCreated(let name): ("Container \(name)", "Created")
        case .containerStarted(let name): ("Container \(name)", "Started")
        case .containerStopped(let name): ("Container \(name)", "Stopped")
        case .containerRemoved(let name): ("Container \(name)", "Removed")
        case .networkRemoved(let name): ("Network \(name)", "Removed")
        }
    }
}

// MARK: - Subcommands

struct ComposeUp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "up",
        abstract: "Create and start containers"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .shortAndLong, help: "Run containers in the background")
    var detach = false

    func run() async throws {
        let (composeFile, project) = try options.loadCompose()
        let config = MockerConfig()
        try config.ensureDirectories()

        let engine = try ContainerEngine(config: config)
        let imageManager = try ImageManager(config: config)
        let networkManager = try NetworkManager(config: config)
        let volumeManager = try VolumeManager(config: config)

        let orchestrator = ComposeOrchestrator(
            projectName: project,
            engine: engine,
            imageManager: imageManager,
            networkManager: networkManager,
            volumeManager: volumeManager
        )

        let totalResources = composeFile.networks.count + composeFile.volumes.count + composeFile.services.count
        let events = try await orchestrator.up(composeFile: composeFile, detach: detach)
        ComposeFormatter.printEvents(events, total: totalResources)
    }
}

struct ComposeDown: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "down",
        abstract: "Stop and remove containers, networks"
    )

    @OptionGroup var options: ComposeOptions

    func run() async throws {
        let (composeFile, project) = try options.loadCompose()
        let config = MockerConfig()

        let engine = try ContainerEngine(config: config)
        let imageManager = try ImageManager(config: config)
        let networkManager = try NetworkManager(config: config)
        let volumeManager = try VolumeManager(config: config)

        let orchestrator = ComposeOrchestrator(
            projectName: project,
            engine: engine,
            imageManager: imageManager,
            networkManager: networkManager,
            volumeManager: volumeManager
        )

        let events = try await orchestrator.down(composeFile: composeFile)
        let totalResources = events.count
        ComposeFormatter.printEvents(events, total: totalResources)
    }
}

struct ComposePS: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ps",
        abstract: "List containers for a compose project"
    )

    @OptionGroup var options: ComposeOptions

    func run() async throws {
        let (_, project) = try options.loadCompose()
        let config = MockerConfig()

        let engine = try ContainerEngine(config: config)
        let imageManager = try ImageManager(config: config)
        let networkManager = try NetworkManager(config: config)
        let volumeManager = try VolumeManager(config: config)

        let orchestrator = ComposeOrchestrator(
            projectName: project,
            engine: engine,
            imageManager: imageManager,
            networkManager: networkManager,
            volumeManager: volumeManager
        )

        let containers = try await orchestrator.ps()

        let headers = ["Name", "Image", "Command", "Service", "Created", "Status", "Ports"]
        let rows = containers.map { c in
            [
                c.name,
                c.image,
                c.command.isEmpty ? "" : "\"\(c.command)\"",
                c.labels["com.mocker.compose.service"] ?? "",
                c.createdAgo,
                c.status,
                c.ports.map(\.description).joined(separator: ", "),
            ]
        }
        TableFormatter.print(headers: headers, rows: rows)
    }
}

struct ComposeLogs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "View output from containers"
    )

    @OptionGroup var options: ComposeOptions

    @Argument(help: "Service name (shows all if omitted)")
    var service: String?

    @Flag(name: .long, help: "Follow log output")
    var follow = false

    func run() async throws {
        let (_, project) = try options.loadCompose()
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        let imageManager = try ImageManager(config: config)
        let networkManager = try NetworkManager(config: config)
        let volumeManager = try VolumeManager(config: config)

        let orchestrator = ComposeOrchestrator(
            projectName: project,
            engine: engine,
            imageManager: imageManager,
            networkManager: networkManager,
            volumeManager: volumeManager
        )

        let containers = try await orchestrator.ps()
        let targets: [ContainerInfo]
        if let service {
            targets = containers.filter { $0.name.contains(service) }
        } else {
            targets = containers
        }

        for container in targets {
            let lines = try await engine.logs(container.id, follow: follow)
            for line in lines {
                print(line)
            }
        }
    }
}

struct ComposeRestart: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restart",
        abstract: "Restart service containers"
    )

    @OptionGroup var options: ComposeOptions

    @Argument(help: "Service name (restarts all if omitted)")
    var service: String?

    func run() async throws {
        let (composeFile, project) = try options.loadCompose()
        let config = MockerConfig()

        let engine = try ContainerEngine(config: config)
        let imageManager = try ImageManager(config: config)
        let networkManager = try NetworkManager(config: config)
        let volumeManager = try VolumeManager(config: config)

        let orchestrator = ComposeOrchestrator(
            projectName: project,
            engine: engine,
            imageManager: imageManager,
            networkManager: networkManager,
            volumeManager: volumeManager
        )

        let events = try await orchestrator.restart(composeFile: composeFile, service: service)
        ComposeFormatter.printEvents(events, total: events.count)
    }
}
