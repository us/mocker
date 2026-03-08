import ArgumentParser
import MockerKit

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create and run a new container"
    )

    @Argument(help: "Image to run")
    var image: String

    @Argument(help: "Command to execute in the container")
    var command: [String] = []

    @Option(name: .long, help: "Assign a name to the container")
    var name: String?

    @Flag(name: .shortAndLong, help: "Run container in background")
    var detach = false

    @Flag(name: .short, help: "Keep STDIN open")
    var interactive = false

    @Flag(name: .short, help: "Allocate a pseudo-TTY")
    var tty = false

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Set environment variables (KEY=VALUE)")
    var env: [String] = []

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Publish container port (hostPort:containerPort)")
    var publish: [String] = []

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Bind mount a volume (source:destination[:ro])")
    var volume: [String] = []

    @Option(name: .long, help: "Connect to a network")
    var network: String?

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Set metadata labels (key=value)")
    var label: [String] = []

    @Option(name: .shortAndLong, help: "Working directory inside the container")
    var workdir: String?

    @Option(name: .long, help: "Container hostname")
    var hostname: String?

    @Option(name: .long, help: "Restart policy (no, always, on-failure, unless-stopped)")
    var restart: String = "no"

    @Flag(name: .long, help: "Automatically remove the container when it exits")
    var rm = false

    func run() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()
        let engine = try ContainerEngine(config: config)

        let environment = Dictionary(
            env.compactMap { item -> (String, String)? in
                let parts = item.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return (String(parts[0]), String(parts[1]))
            },
            uniquingKeysWith: { _, last in last }
        )

        let ports = try publish.map { try PortMapping.parse($0) }
        let volumes = try volume.map { try VolumeMount.parse($0) }
        let labels = Dictionary(
            label.compactMap { item -> (String, String)? in
                let parts = item.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return (String(parts[0]), String(parts[1]))
            },
            uniquingKeysWith: { _, last in last }
        )

        let restartPolicy = RestartPolicy(rawValue: restart) ?? .no

        let containerConfig = ContainerConfig(
            name: name,
            image: image,
            command: command,
            environment: environment,
            ports: ports,
            volumes: volumes,
            network: network,
            detach: detach,
            interactive: interactive,
            tty: tty,
            labels: labels,
            workingDir: workdir,
            hostname: hostname,
            restartPolicy: restartPolicy
        )

        let container = try await engine.run(containerConfig)

        if detach {
            // Detached mode: print full container ID
            print(container.id)
        } else {
            // Foreground mode: show container output
            let lines = try await engine.logs(container.id)
            for line in lines {
                print(line)
            }
            if rm {
                _ = try? await engine.remove(container.id, force: true)
            }
        }
    }
}
