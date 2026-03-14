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
            ComposeKill.self,
            ComposeBuildCommand.self,
            ComposePull.self,
            ComposePush.self,
            ComposeExec.self,
            ComposeRun.self,
            ComposeStop.self,
            ComposeStart.self,
            ComposeRm.self,
            ComposeConfig.self,
            ComposeCreate.self,
            ComposeImages.self,
            ComposeTop.self,
            ComposePort.self,
            ComposePause.self,
            ComposeUnpause.self,
            ComposeLs.self,
            ComposeCp.self,
            ComposeEvents.self,
            ComposeAttach.self,
            ComposeCommit.self,
            ComposeExport.self,
            ComposeScale.self,
            ComposeStats.self,
            ComposeVersion.self,
            ComposeVolumes.self,
            ComposeWait.self,
            ComposeWatch.self,
            ComposeBridge.self,
            ComposePublish.self,
        ]
    )
}

// MARK: - Shared Options

struct ComposeOptions: ParsableArguments {
    @Option(name: [.customShort("f"), .long], help: "Compose file path")
    var file: String?

    @Option(name: [.customShort("p"), .customLong("project-name")], help: "Project name")
    var projectName: String?

    func loadCompose() throws -> (ComposeFile, String) {
        guard let path = file ?? ComposeFile.findDefault() else {
            let searched = ComposeFile.defaultFileNames.joined(separator: ", ")
            throw MockerError.composeFileNotFound("No compose file found. Searched for: \(searched)")
        }
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

    @Flag(name: .customLong("abort-on-container-exit"), help: "Stops all containers if any container was stopped")
    var abortOnContainerExit = false

    @Flag(name: .customLong("abort-on-container-failure"), help: "Stops all containers if any container exited with failure")
    var abortOnContainerFailure = false

    @Flag(name: .customLong("always-recreate-deps"), help: "Recreate dependent containers")
    var alwaysRecreateDeps = false

    @Option(name: .customLong("attach"), parsing: .singleValue, help: "Restrict attaching to the specified services")
    var attachServices: [String] = []

    @Flag(name: .customLong("attach-dependencies"), help: "Automatically attach to log output of dependent services")
    var attachDependencies = false

    @Flag(name: .long, help: "Build images before starting containers")
    var build = false

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .customLong("exit-code-from"), help: "Return the exit code of the selected service container")
    var exitCodeFrom: String?

    @Flag(name: .customLong("force-recreate"), help: "Recreate containers even if configuration hasn't changed")
    var forceRecreate = false

    @Flag(name: .long, help: "Enable interactive shortcuts")
    var menu = false

    @Option(name: .customLong("no-attach"), parsing: .singleValue, help: "Do not attach to the specified services")
    var noAttach: [String] = []

    @Flag(name: .customLong("no-build"), help: "Don't build an image, even if it's policy")
    var noBuild = false

    @Flag(name: .customLong("no-color"), help: "Produce monochrome output")
    var noColor = false

    @Flag(name: .customLong("no-deps"), help: "Don't start linked services")
    var noDeps = false

    @Flag(name: .customLong("no-log-prefix"), help: "Don't print prefix in logs")
    var noLogPrefix = false

    @Flag(name: .customLong("no-recreate"), help: "If containers already exist, don't recreate them")
    var noRecreate = false

    @Flag(name: .customLong("no-start"), help: "Don't start the services after creating them")
    var noStart = false

    @Option(name: .customLong("pull"), help: "Pull image before running (always|missing|never)")
    var pullPolicy: String?

    @Flag(name: .customLong("quiet-build"), help: "Suppress build output")
    var quietBuild = false

    @Flag(name: .customLong("quiet-pull"), help: "Pull without printing progress information")
    var quietPull = false

    @Flag(name: .customLong("remove-orphans"), help: "Remove containers for services not defined in the Compose file")
    var removeOrphans = false

    @Flag(name: [.customShort("V"), .customLong("renew-anon-volumes")], help: "Recreate anonymous volumes")
    var renewAnonVolumes = false

    @Option(name: .long, parsing: .singleValue, help: "Scale SERVICE to NUM instances")
    var scale: [String] = []

    @Option(name: .shortAndLong, help: "Use this timeout in seconds for container shutdown")
    var timeout: Int?

    @Flag(name: .long, help: "Add timestamps to log output")
    var timestamps = false

    @Flag(name: .shortAndLong, help: "Wait for services to be running|healthy")
    var wait = false

    @Option(name: .customLong("wait-timeout"), help: "Maximum duration to wait for the project to be running|healthy")
    var waitTimeout: Int?

    @Flag(name: .long, help: "Watch source code and rebuild/refresh containers when files are updated")
    var watch = false

    @Flag(name: .shortAndLong, help: "Assume yes to all prompts")
    var yes = false

    @Argument(help: "Services to start (starts all if omitted)")
    var services: [String] = []

    func run() async throws {
        var (composeFile, project) = try options.loadCompose()
        let config = MockerConfig()
        try config.ensureDirectories()

        // Filter to requested services only
        if !services.isEmpty {
            composeFile = composeFile.filtering(services: services)
        }

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

    @Flag(name: .customLong("remove-orphans"), help: "Remove containers for services not defined in the Compose file")
    var removeOrphans = false

    @Flag(name: .shortAndLong, help: "Remove named volumes")
    var volumes = false

    @Option(name: .shortAndLong, help: "Timeout in seconds for stopping containers")
    var timeout: Int = 10

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .long, help: "Remove images used by services (all|local)")
    var rmi: String?

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

    @Flag(name: .shortAndLong, help: "Show all stopped containers")
    var all = false

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .long, parsing: .singleValue, help: "Filter services by a property")
    var filter: [String] = []

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    @Flag(name: .customLong("no-trunc"), help: "Don't truncate output")
    var noTrunc = false

    @Flag(name: .long, help: "Include orphaned containers")
    var orphans = false

    @Flag(name: .shortAndLong, help: "Only display IDs")
    var quiet = false

    @Flag(name: .customLong("services"), help: "Display the services")
    var servicesOnly = false

    @Option(name: .long, parsing: .singleValue, help: "Filter services by status")
    var status: [String] = []

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

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .long, help: "Show logs for a specific container index")
    var index: Int?

    @Flag(name: .customLong("no-color"), help: "Produce monochrome output")
    var noColor = false

    @Flag(name: .customLong("no-log-prefix"), help: "Don't print prefix in logs")
    var noLogPrefix = false

    @Option(name: .long, help: "Show logs since timestamp")
    var since: String?

    @Option(name: [.customShort("n"), .long], help: "Number of lines to show from the end of the logs")
    var tail: String?

    @Flag(name: .shortAndLong, help: "Show timestamps")
    var timestamps = false

    @Option(name: .long, help: "Show logs before a timestamp")
    var until: String?

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

struct ComposeKill: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kill",
        abstract: "Force stop service containers"
    )

    @OptionGroup var options: ComposeOptions

    @Argument(help: "Service name (kills all if omitted)")
    var service: String?

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Flag(name: .customLong("remove-orphans"), help: "Remove containers for services not defined in the Compose file")
    var removeOrphans = false

    @Option(name: .shortAndLong, help: "SIGNAL to send to the container")
    var signal: String?

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
        let targets = service.map { s in containers.filter { $0.name.contains(s) } } ?? containers
        for c in targets {
            try? await engine.stop(c.id)
            print(c.name)
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

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Flag(name: .customLong("no-deps"), help: "Don't restart dependent services")
    var noDeps = false

    @Option(name: .shortAndLong, help: "Specify a shutdown timeout in seconds")
    var timeout: Int?

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

// MARK: - Compose Build

struct ComposeBuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build or rebuild services"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("no-cache"), help: "Do not use cache when building the image")
    var noCache = false

    @Flag(name: .long, help: "Always attempt to pull a newer version of the image")
    var pull = false

    @Option(name: .customLong("build-arg"), parsing: .singleValue, help: "Set build-time variables")
    var buildArg: [String] = []

    @Flag(name: .shortAndLong, help: "Suppress the build output")
    var quiet = false

    @Option(name: .long, help: "Set builder to use")
    var builder: String?

    @Flag(name: .long, help: "Check build configuration and exit")
    var check = false

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .shortAndLong, help: "Set memory limit for the build container")
    var memory: String?

    @Flag(name: .customLong("print"), help: "Print equivalent bake file")
    var printBakeFile = false

    @Option(name: .long, help: "Set type of provenance attestation")
    var provenance: String?

    @Flag(name: .customLong("push"), help: "Push service images after build")
    var pushAfterBuild = false

    @Option(name: .long, help: "Set type of SBOM attestation")
    var sbom: String?

    @Option(name: .long, help: "Set SSH authentications used during build")
    var ssh: String?

    @Flag(name: .customLong("with-dependencies"), help: "Also build dependencies")
    var withDependencies = false

    @Argument(help: "Services to build (builds all if omitted)")
    var services: [String] = []

    func run() async throws {
        let (composeFile, _) = try options.loadCompose()
        let config = MockerConfig()
        let manager = try ImageManager(config: config)

        let servicesToBuild = services.isEmpty
            ? composeFile.services.filter { $0.value.build != nil }
            : composeFile.services.filter { services.contains($0.key) && $0.value.build != nil }

        for (name, service) in servicesToBuild {
            guard let buildConfig = service.build else { continue }
            let tag = service.image ?? "\(name):latest"
            if !quiet { print("Building \(name)...") }
            _ = try await manager.build(
                tag: tag, context: buildConfig.context,
                dockerfile: buildConfig.dockerfile ?? "Dockerfile",
                noCache: noCache, buildArgs: buildArg
            )
            if !quiet { print("Successfully built \(name)") }
        }
    }
}

// MARK: - Compose Pull

struct ComposePull: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Pull service images"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .shortAndLong, help: "Suppress pull output")
    var quiet = false

    @Flag(name: .customLong("ignore-pull-failures"), help: "Pull what it can and ignores images with pull failures")
    var ignorePullFailures = false

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Flag(name: .customLong("ignore-buildable"), help: "Ignore images that can be built")
    var ignoreBuildable = false

    @Flag(name: .customLong("include-deps"), help: "Also pull services declared as dependencies")
    var includeDeps = false

    @Option(name: .long, help: "Apply pull policy (missing|always)")
    var policy: String?

    @Argument(help: "Services to pull (pulls all if omitted)")
    var services: [String] = []

    func run() async throws {
        let (composeFile, _) = try options.loadCompose()
        let config = MockerConfig()
        let manager = try ImageManager(config: config)

        let servicesToPull = services.isEmpty
            ? composeFile.services
            : composeFile.services.filter { services.contains($0.key) }

        for (name, service) in servicesToPull {
            guard let image = service.image else { continue }
            do {
                if !quiet { print("Pulling \(name) (\(image))...") }
                _ = try await manager.pull(image)
                if !quiet { print("Pulled \(name)") }
            } catch {
                if ignorePullFailures {
                    if !quiet { print("WARNING: pull failed for \(name): \(error.localizedDescription)") }
                } else {
                    throw error
                }
            }
        }
    }
}

// MARK: - Compose Push

struct ComposePush: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "push",
        abstract: "Push service images"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("ignore-push-failures"), help: "Push what it can and ignores images with push failures")
    var ignorePushFailures = false

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Flag(name: .customLong("include-deps"), help: "Also push images of services declared as dependencies")
    var includeDeps = false

    @Flag(name: .shortAndLong, help: "Push without printing progress information")
    var quiet = false

    @Argument(help: "Services to push (pushes all if omitted)")
    var services: [String] = []

    func run() async throws {
        let (composeFile, _) = try options.loadCompose()
        let config = MockerConfig()
        let manager = try ImageManager(config: config)

        let servicesToPush = services.isEmpty
            ? composeFile.services
            : composeFile.services.filter { services.contains($0.key) }

        for (name, service) in servicesToPush {
            guard let image = service.image else { continue }
            do {
                print("Pushing \(name) (\(image))...")
                try await manager.push(image)
                print("Pushed \(name)")
            } catch {
                if ignorePushFailures {
                    print("WARNING: push failed for \(name): \(error.localizedDescription)")
                } else {
                    throw error
                }
            }
        }
    }
}

// MARK: - Compose Exec

struct ComposeExec: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exec",
        abstract: "Execute a command in a running service container"
    )

    @OptionGroup var options: ComposeOptions

    @Argument(help: "Service name")
    var service: String

    @Argument(help: "Command to execute")
    var command: [String]

    @Flag(name: .shortAndLong, help: "Detached mode")
    var detach = false

    @Flag(name: .short, help: "Keep STDIN open")
    var interactive = false

    @Flag(name: .short, help: "Allocate a pseudo-TTY")
    var tty = false

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Set environment variables")
    var env: [String] = []

    @Option(name: .shortAndLong, help: "Username or UID")
    var user: String?

    @Option(name: .shortAndLong, help: "Working directory inside the container")
    var workdir: String?

    @Option(name: .long, help: "Index of the container if service is scaled")
    var index: Int = 1

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Flag(name: [.customShort("T"), .customLong("no-tty")], help: "Disable pseudo-TTY allocation")
    var noTty = false

    @Flag(name: .long, help: "Give extended privileges to the process")
    var privileged = false

    func run() async throws {
        let (_, project) = try options.loadCompose()
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        let containerName = "\(project)-\(service)-\(index)"
        try await engine.exec(containerName, command: command, interactive: interactive, tty: tty)
    }
}

// MARK: - Compose Run

struct ComposeRun: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a one-off command on a service"
    )

    @OptionGroup var options: ComposeOptions

    @Argument(help: "Service name")
    var service: String

    @Argument(help: "Command to execute")
    var command: [String] = []

    @Flag(name: .shortAndLong, help: "Run container in background")
    var detach = false

    @Flag(name: .long, help: "Remove container after run")
    var rm = false

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Set environment variables")
    var env: [String] = []

    @Option(name: .shortAndLong, help: "Username or UID")
    var user: String?

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Bind mount a volume")
    var volume: [String] = []

    @Option(name: .long, parsing: .singleValue, help: "Publish a container's port")
    var publish: [String] = []

    @Option(name: .shortAndLong, help: "Working directory inside the container")
    var workdir: String?

    @Option(name: .long, help: "Override the entrypoint")
    var entrypoint: String?

    @Flag(name: .customLong("no-deps"), help: "Don't start linked services")
    var noDeps = false

    @Flag(name: .long, help: "Build images before starting containers")
    var build = false

    @Option(name: .customLong("cap-add"), parsing: .singleValue, help: "Add Linux capabilities")
    var capAdd: [String] = []

    @Option(name: .customLong("cap-drop"), parsing: .singleValue, help: "Drop Linux capabilities")
    var capDrop: [String] = []

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .customLong("env-from-file"), parsing: .singleValue, help: "Set environment variables from file")
    var envFromFile: [String] = []

    @Flag(name: .shortAndLong, help: "Keep STDIN open even if not attached")
    var interactive = false

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Add or override a label")
    var label: [String] = []

    @Option(name: .long, help: "Assign a name to the container")
    var name: String?

    @Flag(name: [.customShort("T"), .customLong("no-tty")], help: "Disable pseudo-TTY allocation")
    var noTty = false

    @Option(name: .customLong("pull"), help: "Pull image before running (always|missing|never)")
    var pullPolicy: String?

    @Flag(name: .shortAndLong, help: "Suppress run output")
    var quiet = false

    @Flag(name: .customLong("quiet-build"), help: "Suppress build output")
    var quietBuild = false

    @Flag(name: .customLong("quiet-pull"), help: "Pull without printing progress information")
    var quietPull = false

    @Flag(name: .customLong("remove-orphans"), help: "Remove containers for services not defined in the Compose file")
    var removeOrphans = false

    @Flag(name: .customLong("service-ports"), help: "Run command with all service's ports enabled and mapped to the host")
    var servicePorts = false

    @Flag(name: .shortAndLong, help: "Allocate a pseudo-TTY")
    var tty = false

    @Flag(name: .customLong("use-aliases"), help: "Use the service's network useAliases in the network(s) the container connects to")
    var useAliases = false

    @Flag(name: [.customShort("P"), .customLong("publish-all")], help: "Publish all exposed ports to random host ports")
    var publishAll = false

    func run() async throws {
        let (composeFile, _) = try options.loadCompose()
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        guard let svc = composeFile.services[service] else {
            throw MockerError.operationFailed("no such service: \(service)")
        }

        guard let image = svc.image else {
            throw MockerError.operationFailed("service \(service) has no image")
        }

        var environment: [String: String] = [:]
        for item in env {
            let parts = item.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            environment[String(parts[0])] = String(parts[1])
        }

        let containerConfig = ContainerConfig(
            image: image,
            command: command,
            environment: environment,
            detach: detach,
            workingDir: workdir,
            entrypoint: entrypoint
        )

        let container = try await engine.run(containerConfig)
        if detach {
            print(container.id)
        } else {
            let lines = try await engine.logs(container.id)
            for line in lines { print(line) }
            if rm {
                _ = try? await engine.remove(container.id, force: true)
            }
        }
    }
}

// MARK: - Compose Stop

struct ComposeStop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop services"
    )

    @OptionGroup var options: ComposeOptions

    @Option(name: .shortAndLong, help: "Specify a shutdown timeout in seconds")
    var timeout: Int = 10

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Argument(help: "Services to stop (stops all if omitted)")
    var services: [String] = []

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
        let targets = services.isEmpty
            ? containers
            : containers.filter { c in services.contains(where: { c.name.contains($0) }) }

        for c in targets {
            _ = try? await engine.stop(c.id)
            print("Container \(c.name)  Stopped")
        }
    }
}

// MARK: - Compose Start

struct ComposeStart: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start services"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Flag(name: .long, help: "Wait for services to be running|healthy")
    var wait = false

    @Option(name: .customLong("wait-timeout"), help: "Maximum duration to wait for the project to be running|healthy")
    var waitTimeout: Int?

    @Argument(help: "Services to start (starts all if omitted)")
    var services: [String] = []

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
        let targets = services.isEmpty
            ? containers
            : containers.filter { c in services.contains(where: { c.name.contains($0) }) }

        for c in targets {
            _ = try? await engine.start(c.id)
            print("Container \(c.name)  Started")
        }
    }
}

// MARK: - Compose Rm

struct ComposeRm: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove stopped service containers"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .long, help: "Don't ask to confirm removal")
    var force = false

    @Flag(name: [.customShort("s"), .customLong("stop")], help: "Stop the containers, if required, before removing")
    var stopBeforeRemove = false

    @Flag(name: [.customShort("v"), .long], help: "Remove any anonymous volumes attached to containers")
    var volumes = false

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Argument(help: "Services to remove (removes all if omitted)")
    var services: [String] = []

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
        let targets = services.isEmpty
            ? containers
            : containers.filter { c in services.contains(where: { c.name.contains($0) }) }

        for c in targets {
            if stopBeforeRemove { _ = try? await engine.stop(c.id) }
            _ = try? await engine.remove(c.id, force: force)
            print("Container \(c.name)  Removed")
        }
    }
}

// MARK: - Compose Config

struct ComposeConfig: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Validate and view the Compose file"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .long, help: "Print the service names, one per line")
    var services = false

    @Flag(name: .customLong("volumes"), help: "Print the volume names, one per line")
    var volumesList = false

    @Flag(name: .shortAndLong, help: "Only validate the configuration, don't print anything")
    var quiet = false

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Flag(name: .long, help: "Print the environment variables")
    var environment = false

    @Option(name: .long, help: "Format the output (yaml|json)")
    var format: String?

    @Option(name: .long, help: "Print the service config hash")
    var hash: String?

    @Flag(name: .customLong("images"), help: "Print the image names, one per line")
    var imagesList = false

    @Flag(name: .customLong("lock-image-digests"), help: "Pin image tags to digests")
    var lockImageDigests = false

    @Flag(name: .long, help: "Print the model names, one per line")
    var models = false

    @Flag(name: .customLong("networks"), help: "Print the network names, one per line")
    var networksList = false

    @Flag(name: .customLong("no-consistency"), help: "Don't check model consistency")
    var noConsistency = false

    @Flag(name: .customLong("no-env-resolution"), help: "Don't resolve environment variables")
    var noEnvResolution = false

    @Flag(name: .customLong("no-interpolate"), help: "Don't interpolate environment variables")
    var noInterpolate = false

    @Flag(name: .customLong("no-normalize"), help: "Don't normalize compose model")
    var noNormalize = false

    @Flag(name: .customLong("no-path-resolution"), help: "Don't resolve file paths")
    var noPathResolution = false

    @Option(name: .shortAndLong, help: "Save to file")
    var output: String?

    @Flag(name: .long, help: "Print the profile names, one per line")
    var profiles = false

    @Flag(name: .customLong("resolve-image-digests"), help: "Pin image tags to digests")
    var resolveImageDigests = false

    @Flag(name: .long, help: "Print the variable names, one per line")
    var variables = false

    func run() async throws {
        let (composeFile, _) = try options.loadCompose()

        if quiet { return }

        if services {
            for name in composeFile.services.keys.sorted() {
                print(name)
            }
            return
        }

        if volumesList {
            for name in composeFile.volumes.keys.sorted() {
                print(name)
            }
            return
        }

        // Print resolved compose file as YAML-like output
        print("name: \(options.projectName ?? "default")")
        print("services:")
        for (name, svc) in composeFile.services.sorted(by: { $0.key < $1.key }) {
            print("  \(name):")
            if let image = svc.image { print("    image: \(image)") }
            if let build = svc.build { print("    build: \(build)") }
            if !svc.ports.isEmpty { print("    ports:"); svc.ports.forEach { print("      - \($0)") } }
            if !svc.environment.isEmpty { print("    environment:"); svc.environment.forEach { print("      - \($0)") } }
        }
    }
}

// MARK: - Compose Create

struct ComposeCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create containers for a service"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .long, help: "Build images before starting containers")
    var build = false

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Flag(name: .customLong("force-recreate"), help: "Recreate containers even if configuration hasn't changed")
    var forceRecreate = false

    @Flag(name: .customLong("no-build"), help: "Don't build an image, even if it's policy")
    var noBuild = false

    @Flag(name: .customLong("no-recreate"), help: "If containers already exist, don't recreate them")
    var noRecreate = false

    @Option(name: .long, help: "Pull image before running (always|missing|never)")
    var pull: String?

    @Flag(name: .customLong("quiet-pull"), help: "Pull without printing progress information")
    var quietPull = false

    @Flag(name: .customLong("remove-orphans"), help: "Remove containers for services not defined in the Compose file")
    var removeOrphans = false

    @Option(name: .long, parsing: .singleValue, help: "Scale SERVICE to NUM instances")
    var scale: [String] = []

    @Flag(name: .shortAndLong, help: "Assume yes to all prompts")
    var yes = false

    @Argument(help: "Services to create (creates all if omitted)")
    var services: [String] = []

    func run() async throws {
        // create is essentially up without starting — for now delegate to up
        var (composeFile, project) = try options.loadCompose()
        let config = MockerConfig()
        try config.ensureDirectories()

        if !services.isEmpty {
            composeFile = composeFile.filtering(services: services)
        }

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

        let events = try await orchestrator.up(composeFile: composeFile, detach: true)
        ComposeFormatter.printEvents(events, total: events.count)
    }
}

// MARK: - Compose Images

struct ComposeImages: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "images",
        abstract: "List images used by created containers"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .long, help: "Format the output (table|json)")
    var format: String?

    @Flag(name: .shortAndLong, help: "Only display IDs")
    var quiet = false

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
        let headers = ["Container", "Repository", "Tag", "Image Id", "Size"]
        let rows = containers.map { c in
            let parts = c.image.split(separator: ":")
            let repo = String(parts.first ?? "")
            let tag = parts.count > 1 ? String(parts[1]) : "latest"
            return [c.name, repo, tag, c.shortID, "N/A"]
        }
        TableFormatter.print(headers: headers, rows: rows)
    }
}

// MARK: - Compose Top

struct ComposeTop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "top",
        abstract: "Display the running processes"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Argument(help: "Services to show (shows all if omitted)")
    var services: [String] = []

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
        let targets = services.isEmpty
            ? containers
            : containers.filter { c in services.contains(where: { c.name.contains($0) }) }

        for c in targets {
            print("\(c.name)")
            let output = try await engine.top(c.id)
            print(output)
            print("")
        }
    }
}

// MARK: - Compose Port

struct ComposePort: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "port",
        abstract: "Print the public port for a port binding"
    )

    @OptionGroup var options: ComposeOptions

    @Argument(help: "Service name")
    var service: String

    @Argument(help: "Private port")
    var privatePort: Int

    @Option(name: .long, help: "Protocol (tcp or udp)")
    var proto: String = "tcp"

    @Option(name: .long, help: "Index of the container if service is scaled")
    var index: Int = 1

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .long, help: "Protocol (tcp or udp)")
    var `protocol`: String?

    func run() async throws {
        let (_, project) = try options.loadCompose()
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        let containerName = "\(project)-\(service)-\(index)"
        let info = try await engine.inspect(containerName)
        if let port = info.ports.first(where: { $0.containerPort == UInt16(privatePort) }) {
            print("0.0.0.0:\(port.hostPort)")
        }
    }
}

// MARK: - Compose Pause / Unpause

struct ComposePause: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pause",
        abstract: "Pause services"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Argument(help: "Services to pause (pauses all if omitted)")
    var services: [String] = []

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
        let targets = services.isEmpty
            ? containers
            : containers.filter { c in services.contains(where: { c.name.contains($0) }) }

        for c in targets {
            try await engine.pause(c.id)
            print("Container \(c.name)  Paused")
        }
    }
}

struct ComposeUnpause: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unpause",
        abstract: "Unpause services"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Argument(help: "Services to unpause (unpauses all if omitted)")
    var services: [String] = []

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
        let targets = services.isEmpty
            ? containers
            : containers.filter { c in services.contains(where: { c.name.contains($0) }) }

        for c in targets {
            try await engine.unpause(c.id)
            print("Container \(c.name)  Unpaused")
        }
    }
}

// MARK: - Compose Ls

struct ComposeLs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List running compose projects"
    )

    @Flag(name: .shortAndLong, help: "Show all stopped compose projects")
    var all = false

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    @Flag(name: .shortAndLong, help: "Only display project names")
    var quiet = false

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .long, parsing: .singleValue, help: "Filter output based on conditions provided")
    var filter: [String] = []

    func run() async throws {
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        let containers = try await engine.list(all: all)

        // Group by compose project label
        var projects: [String: (status: String, count: Int)] = [:]
        for c in containers {
            if let project = c.labels["com.mocker.compose.project"] {
                let existing = projects[project] ?? (status: "running", count: 0)
                projects[project] = (status: existing.status, count: existing.count + 1)
            }
        }

        if quiet {
            for name in projects.keys.sorted() { print(name) }
            return
        }

        let headers = ["NAME", "STATUS", "CONFIG FILES"]
        let rows = projects.sorted(by: { $0.key < $1.key }).map { (name, info) in
            [name, "\(info.status)(\(info.count))", ""]
        }
        TableFormatter.print(headers: headers, rows: rows)
    }
}

// MARK: - Compose Cp

struct ComposeCp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cp",
        abstract: "Copy files/folders between a service container and the local filesystem"
    )

    @OptionGroup var options: ComposeOptions

    @Argument(help: "Source path (service:path or local path)")
    var source: String

    @Argument(help: "Destination path (service:path or local path)")
    var destination: String

    @Option(name: .long, help: "Index of the container if service is scaled")
    var index: Int = 1

    @Flag(name: .shortAndLong, help: "Copy to all containers of the service")
    var all = false

    @Flag(name: .long, help: "Archive mode (copy all uid/gid information)")
    var archive = false

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Flag(name: [.customShort("L"), .customLong("follow-link")], help: "Always follow symbol link in source path")
    var followLink = false

    func run() async throws {
        let (_, project) = try options.loadCompose()
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)

        // Parse service:path format
        let parts = source.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2 && !parts[0].hasPrefix("/") && !parts[0].hasPrefix(".") {
            // Copy from container
            let containerName = "\(project)-\(parts[0])-\(index)"
            let data = try await engine.copyFromContainer(containerName, path: parts[1])
            try data.write(to: URL(fileURLWithPath: destination))
        } else {
            let dstParts = destination.split(separator: ":", maxSplits: 1).map(String.init)
            if dstParts.count == 2 && !dstParts[0].hasPrefix("/") {
                let containerName = "\(project)-\(dstParts[0])-\(index)"
                let data = try Data(contentsOf: URL(fileURLWithPath: source))
                try await engine.copyToContainer(containerName, path: dstParts[1], data: data)
            }
        }
    }
}

// MARK: - Compose Events

struct ComposeEvents: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "Receive real time events from containers"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Flag(name: .long, help: "Output events as a stream of json objects")
    var json = false

    @Option(name: .long, help: "Show all events created since timestamp")
    var since: String?

    @Option(name: .long, help: "Stream events until this timestamp")
    var until: String?

    @Argument(help: "Service names")
    var services: [String] = []

    func run() async throws {
        throw MockerError.operationFailed("compose events is not yet supported with Apple Containerization")
    }
}

// MARK: - Compose Attach

struct ComposeAttach: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attach",
        abstract: "Attach local standard input, output, and error streams to a service's running container"
    )

    @OptionGroup var options: ComposeOptions

    @Option(name: .customLong("detach-keys"), help: "Override the key sequence for detaching from a container")
    var detachKeys: String?

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .long, help: "Index of the container if service has multiple replicas")
    var index: Int?

    @Flag(name: .customLong("no-stdin"), help: "Do not attach STDIN")
    var noStdin = false

    @Flag(name: .customLong("sig-proxy"), help: "Proxy all received signals to the process")
    var sigProxy = false

    @Argument(help: "Service name")
    var service: String

    func run() async throws {
        let (_, project) = try options.loadCompose()
        let config = MockerConfig()
        let engine = try ContainerEngine(config: config)
        let idx = index ?? 1
        let containerName = "\(project)-\(service)-\(idx)"
        try await engine.exec(containerName, command: [])
    }
}

// MARK: - Compose Commit

struct ComposeCommit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "commit",
        abstract: "Create a new image from a service container's changes"
    )

    @OptionGroup var options: ComposeOptions

    @Option(name: [.customShort("a"), .long], help: "Author (e.g., \"John Hannibal Smith <hannibal@a-team.com>\")")
    var author: String?

    @Option(name: [.customShort("c"), .long], parsing: .singleValue, help: "Apply Dockerfile instruction to the created image")
    var change: [String] = []

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .long, help: "Index of the container if service has multiple replicas")
    var index: Int?

    @Option(name: [.customShort("m"), .long], help: "Commit message")
    var message: String?

    @Flag(name: .long, help: "Pause container during commit")
    var pause = false

    @Argument(help: "Service name")
    var service: String

    @Argument(help: "Repository[:tag]")
    var repository: String?

    func run() async throws {
        throw MockerError.operationFailed("compose commit is not yet supported with Apple Containerization")
    }
}

// MARK: - Compose Export

struct ComposeExport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export a service container's filesystem as a tar archive"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .long, help: "Index of the container if service has multiple replicas")
    var index: Int?

    @Option(name: [.customShort("o"), .long], help: "Write to a file, instead of STDOUT")
    var output: String?

    @Argument(help: "Service name")
    var service: String

    func run() async throws {
        throw MockerError.operationFailed("compose export is not yet supported with Apple Containerization")
    }
}

// MARK: - Compose Scale

struct ComposeScale: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scale",
        abstract: "Scale services"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Flag(name: .customLong("no-deps"), help: "Don't start linked services")
    var noDeps = false

    @Argument(help: "Service=num pairs (e.g. web=3)")
    var scales: [String] = []

    func run() async throws {
        throw MockerError.operationFailed("compose scale is not yet supported with Apple Containerization")
    }
}

// MARK: - Compose Stats

struct ComposeStats: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Display a live stream of container(s) resource usage statistics"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .shortAndLong, help: "Show all containers (default shows just running)")
    var all = false

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    @Flag(name: .customLong("no-stream"), help: "Disable streaming stats and only pull the first result")
    var noStream = false

    @Flag(name: .customLong("no-trunc"), help: "Do not truncate output")
    var noTrunc = false

    @Argument(help: "Service names")
    var services: [String] = []

    func run() async throws {
        throw MockerError.operationFailed("compose stats is not yet supported with Apple Containerization")
    }
}

// MARK: - Compose Version

struct ComposeVersion: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Show the Docker Compose version information"
    )

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .shortAndLong, help: "Format the output (pretty|json)")
    var format: String?

    @Flag(name: .long, help: "Shows only Compose's version number")
    var short = false

    func run() async throws {
        print("Mocker Compose version v0.1.9")
    }
}

// MARK: - Compose Volumes

struct ComposeVolumes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "volumes",
        abstract: "List volumes"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    @Flag(name: .shortAndLong, help: "Only display volume names")
    var quiet = false

    func run() async throws {
        let (composeFile, _) = try options.loadCompose()
        for (name, _) in composeFile.volumes {
            print(name)
        }
    }
}

// MARK: - Compose Wait

struct ComposeWait: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wait",
        abstract: "Block until containers of all (or specified) services stop"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("down-project"), help: "Drops project when the first container stops")
    var downProject = false

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Argument(help: "Service names")
    var services: [String] = []

    func run() async throws {
        throw MockerError.operationFailed("compose wait is not yet supported with Apple Containerization")
    }
}

// MARK: - Compose Watch

struct ComposeWatch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Watch build context for service and rebuild/refresh containers when files are updated"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Flag(name: .customLong("no-up"), help: "Do not build & start services before watching")
    var noUp = false

    @Flag(name: .long, help: "Prune dangling images on rebuild")
    var prune = false

    @Flag(name: .shortAndLong, help: "Hide build output")
    var quiet = false

    @Argument(help: "Service names")
    var services: [String] = []

    func run() async throws {
        throw MockerError.operationFailed("compose watch is not yet supported with Apple Containerization")
    }
}

// MARK: - Compose Bridge

struct ComposeBridge: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bridge",
        abstract: "Convert compose files into another model"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    func run() async throws {
        throw MockerError.operationFailed("compose bridge is not yet supported with Apple Containerization")
    }
}

// MARK: - Compose Publish

struct ComposePublish: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Publish compose application"
    )

    @OptionGroup var options: ComposeOptions

    @Flag(name: .long, help: "Published compose application (includes env)")
    var app = false

    @Flag(name: .customLong("dry-run"), help: "Execute command in dry run mode")
    var dryRun = false

    @Option(name: .customLong("oci-version"), help: "OCI image/artifact specification version")
    var ociVersion: String?

    @Flag(name: .customLong("resolve-image-digests"), help: "Pin image tags to digests")
    var resolveImageDigests = false

    @Flag(name: .customLong("with-env"), help: "Include environment variables in the published application")
    var withEnv = false

    @Flag(name: [.customShort("y"), .long], help: "Assume \"yes\" as answer to all prompts")
    var yes = false

    @Argument(help: "Repository for the published image")
    var repository: String

    func run() async throws {
        throw MockerError.operationFailed("compose publish is not yet supported with Apple Containerization")
    }
}
