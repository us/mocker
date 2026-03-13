import ArgumentParser
import MockerKit
import Foundation

struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new container"
    )

    @Argument(help: "Image to use")
    var image: String

    @Argument(help: "Command to execute in the container")
    var command: [String] = []

    @Option(name: .long, help: "Assign a name to the container")
    var name: String?

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Set environment variables (KEY=VALUE)")
    var env: [String] = []

    @Option(name: .long, help: "Read in a file of environment variables")
    var envFile: String?

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

    @Option(name: [.customShort("h"), .long], help: "Container hostname")
    var hostname: String?

    @Option(name: .long, help: "Restart policy (no, always, on-failure, unless-stopped)")
    var restart: String = "no"

    @Flag(name: .shortAndLong, help: "Keep STDIN open even if not attached")
    var interactive = false

    @Flag(name: .shortAndLong, help: "Allocate a pseudo-TTY")
    var tty = false

    @Option(name: .shortAndLong, help: "Username or UID (format: <name|uid>[:<group|gid>])")
    var user: String?

    @Option(name: .long, help: "Overwrite the default ENTRYPOINT of the image")
    var entrypoint: String?

    @Option(name: .long, help: "Set platform (e.g. linux/amd64, linux/arm64)")
    var platform: String?

    @Option(name: .long, help: "Pull image before creating (\"always\", \"missing\", \"never\")")
    var pull: String = "missing"

    @Flag(name: .long, help: "Run an init inside the container")
    var `init` = false

    @Option(name: .long, parsing: .singleValue, help: "Set custom DNS servers")
    var dns: [String] = []

    @Option(name: .customLong("add-host"), parsing: .singleValue, help: "Add a custom host-to-IP mapping (host:ip)")
    var addHost: [String] = []

    @Option(name: .long, parsing: .singleValue, help: "Attach a filesystem mount to the container")
    var mount: [String] = []

    @Flag(name: .customLong("read-only"), help: "Mount the container's root filesystem as read only")
    var readOnly = false

    @Option(name: .long, parsing: .singleValue, help: "Mount a tmpfs directory")
    var tmpfs: [String] = []

    @Option(name: .customLong("shm-size"), help: "Size of /dev/shm")
    var shmSize: String?

    @Flag(name: .long, help: "Give extended privileges to this container")
    var privileged = false

    @Option(name: .customLong("cap-add"), parsing: .singleValue, help: "Add Linux capabilities")
    var capAdd: [String] = []

    @Option(name: .customLong("cap-drop"), parsing: .singleValue, help: "Drop Linux capabilities")
    var capDrop: [String] = []

    @Option(name: .customLong("stop-signal"), help: "Signal to stop the container")
    var stopSignal: String = "SIGTERM"

    @Option(name: .customLong("stop-timeout"), help: "Timeout (in seconds) to stop a container")
    var stopTimeout: Int?

    @Option(name: .shortAndLong, help: "Memory limit (e.g. 512m, 1g)")
    var memory: String?

    @Option(name: .long, help: "Number of CPUs")
    var cpus: String?

    @Flag(name: .long, help: "Automatically remove the container when it exits")
    var rm = false

    // --- Additional Docker-compatible flags ---

    @Option(name: .long, parsing: .singleValue, help: "Add an annotation to the container (passed through to the OCI runtime)")
    var annotation: [String] = []

    @Option(name: [.customShort("a"), .long], parsing: .singleValue, help: "Attach to STDIN, STDOUT or STDERR")
    var attach: [String] = []

    @Option(name: .customLong("blkio-weight"), help: "Block IO (relative weight), between 10 and 1000, or 0 to disable")
    var blkioWeight: Int?

    @Option(name: .customLong("blkio-weight-device"), parsing: .singleValue, help: "Block IO weight (relative device weight)")
    var blkioWeightDevice: [String] = []

    @Option(name: .customLong("cgroup-parent"), help: "Optional parent cgroup for the container")
    var cgroupParent: String?

    @Option(name: .customLong("cgroupns"), help: "Cgroup namespace to use (host|private)")
    var cgroupns: String?

    @Option(name: .customLong("cidfile"), help: "Write the container ID to the file")
    var cidfile: String?

    @Option(name: [.customShort("c"), .customLong("cpu-shares")], help: "CPU shares (relative weight)")
    var cpuShares: Int?

    @Option(name: .customLong("cpu-period"), help: "Limit CPU CFS (Completely Fair Scheduler) period")
    var cpuPeriod: Int?

    @Option(name: .customLong("cpu-quota"), help: "Limit CPU CFS (Completely Fair Scheduler) quota")
    var cpuQuota: Int?

    @Option(name: .customLong("cpu-rt-period"), help: "Limit CPU real-time period in microseconds")
    var cpuRtPeriod: Int?

    @Option(name: .customLong("cpu-rt-runtime"), help: "Limit CPU real-time runtime in microseconds")
    var cpuRtRuntime: Int?

    @Option(name: .customLong("cpuset-cpus"), help: "CPUs in which to allow execution (0-3, 0,1)")
    var cpusetCpus: String?

    @Option(name: .customLong("cpuset-mems"), help: "MEMs in which to allow execution (0-3, 0,1)")
    var cpusetMems: String?

    @Option(name: .long, parsing: .singleValue, help: "Add a host device to the container")
    var device: [String] = []

    @Option(name: .customLong("device-cgroup-rule"), parsing: .singleValue, help: "Add a rule to the cgroup allowed devices list")
    var deviceCgroupRule: [String] = []

    @Option(name: .customLong("device-read-bps"), parsing: .singleValue, help: "Limit read rate (bytes per second) from a device")
    var deviceReadBps: [String] = []

    @Option(name: .customLong("device-read-iops"), parsing: .singleValue, help: "Limit read rate (IO per second) from a device")
    var deviceReadIops: [String] = []

    @Option(name: .customLong("device-write-bps"), parsing: .singleValue, help: "Limit write rate (bytes per second) to a device")
    var deviceWriteBps: [String] = []

    @Option(name: .customLong("device-write-iops"), parsing: .singleValue, help: "Limit write rate (IO per second) to a device")
    var deviceWriteIops: [String] = []

    @Option(name: .customLong("dns-option"), parsing: .singleValue, help: "Set DNS options")
    var dnsOption: [String] = []

    @Option(name: .customLong("dns-search"), parsing: .singleValue, help: "Set custom DNS search domains")
    var dnsSearch: [String] = []

    @Option(name: .long, help: "Container NIS domain name")
    var domainname: String?

    @Option(name: .long, parsing: .singleValue, help: "Expose a port or a range of ports")
    var expose: [String] = []

    @Option(name: .long, help: "GPU devices to add to the container ('all' to pass all GPUs)")
    var gpus: String?

    @Option(name: .customLong("group-add"), parsing: .singleValue, help: "Add additional groups to join")
    var groupAdd: [String] = []

    @Option(name: .customLong("health-cmd"), help: "Command to run to check health")
    var healthCmd: String?

    @Option(name: .customLong("health-interval"), help: "Time between running the check (ms|s|m|h)")
    var healthInterval: String?

    @Option(name: .customLong("health-retries"), help: "Consecutive failures needed to report unhealthy")
    var healthRetries: Int?

    @Option(name: .customLong("health-start-interval"), help: "Time between running the check during the start period (ms|s|m|h)")
    var healthStartInterval: String?

    @Option(name: .customLong("health-start-period"), help: "Start period for the container to initialize before starting health-retries countdown (ms|s|m|h)")
    var healthStartPeriod: String?

    @Option(name: .customLong("health-timeout"), help: "Maximum time to allow one check to run (ms|s|m|h)")
    var healthTimeout: String?

    @Option(name: .long, help: "IPv4 address (e.g., 172.30.100.104)")
    var ip: String?

    @Option(name: .long, help: "IPv6 address (e.g., 2001:db8::33)")
    var ip6: String?

    @Option(name: .long, help: "IPC mode to use")
    var ipc: String?

    @Option(name: .long, help: "Container isolation technology")
    var isolation: String?

    @Option(name: .customLong("label-file"), parsing: .singleValue, help: "Read in a line delimited file of labels")
    var labelFile: [String] = []

    @Option(name: .long, parsing: .singleValue, help: "Add link to another container")
    var link: [String] = []

    @Option(name: .customLong("link-local-ip"), parsing: .singleValue, help: "Container IPv4/IPv6 link-local addresses")
    var linkLocalIp: [String] = []

    @Option(name: .customLong("log-driver"), help: "Logging driver for the container")
    var logDriver: String?

    @Option(name: .customLong("log-opt"), parsing: .singleValue, help: "Log driver options")
    var logOpt: [String] = []

    @Option(name: .customLong("mac-address"), help: "Container MAC address (e.g., 92:d0:c6:0a:29:33)")
    var macAddress: String?

    @Option(name: .customLong("memory-reservation"), help: "Memory soft limit")
    var memoryReservation: String?

    @Option(name: .customLong("memory-swap"), help: "Swap limit equal to memory plus swap: -1 to enable unlimited swap")
    var memorySwap: String?

    @Option(name: .customLong("memory-swappiness"), help: "Tune container memory swappiness (0 to 100)")
    var memorySwappiness: Int?

    @Option(name: .customLong("network-alias"), parsing: .singleValue, help: "Add network-scoped alias for the container")
    var networkAlias: [String] = []

    @Flag(name: .customLong("no-healthcheck"), help: "Disable any container-specified HEALTHCHECK")
    var noHealthcheck = false

    @Flag(name: .customLong("oom-kill-disable"), help: "Disable OOM Killer")
    var oomKillDisable = false

    @Option(name: .customLong("oom-score-adj"), help: "Tune host's OOM preferences (-1000 to 1000)")
    var oomScoreAdj: Int?

    @Option(name: .long, help: "PID namespace to use")
    var pid: String?

    @Option(name: .customLong("pids-limit"), help: "Tune container pids limit (set -1 for unlimited)")
    var pidsLimit: Int?

    @Flag(name: [.customShort("P"), .customLong("publish-all")], help: "Publish all exposed ports to random ports")
    var publishAll = false

    @Flag(name: [.customShort("q"), .long], help: "Suppress the pull output")
    var quiet = false

    @Option(name: .long, help: "Runtime to use for this container")
    var runtime: String?

    @Option(name: .customLong("security-opt"), parsing: .singleValue, help: "Security Options")
    var securityOpt: [String] = []

    @Option(name: .customLong("storage-opt"), parsing: .singleValue, help: "Storage driver options for the container")
    var storageOpt: [String] = []

    @Option(name: .long, parsing: .singleValue, help: "Sysctl options")
    var sysctl: [String] = []

    @Option(name: .long, parsing: .singleValue, help: "Ulimit options")
    var ulimit: [String] = []

    @Flag(name: .customLong("use-api-socket"), help: "Bind mount Docker API socket and set DOCKER_HOST")
    var useApiSocket = false

    @Option(name: .long, help: "User namespace to use")
    var userns: String?

    @Option(name: .long, help: "UTS namespace to use")
    var uts: String?

    @Option(name: .customLong("volume-driver"), help: "Optional volume driver for the container")
    var volumeDriver: String?

    @Option(name: .customLong("volumes-from"), parsing: .singleValue, help: "Mount volumes from the specified container(s)")
    var volumesFrom: [String] = []

    func run() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()
        let engine = try ContainerEngine(config: config)

        var environment: [String: String] = [:]

        if let envFilePath = envFile {
            let fileURL = URL(fileURLWithPath: envFilePath)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                environment[String(parts[0])] = String(parts[1])
            }
        }

        for item in env {
            let parts = item.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            environment[String(parts[0])] = String(parts[1])
        }

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
            detach: true,
            interactive: interactive,
            tty: tty,
            labels: labels,
            workingDir: workdir,
            hostname: hostname,
            restartPolicy: restartPolicy,
            user: user,
            entrypoint: entrypoint,
            platform: platform,
            dns: dns,
            addHost: addHost,
            privileged: privileged,
            capAdd: capAdd,
            capDrop: capDrop,
            readOnly: readOnly,
            tmpfs: tmpfs,
            shmSize: shmSize,
            stopSignal: stopSignal,
            stopTimeout: stopTimeout,
            memory: memory,
            cpus: cpus
        )

        let container = try await engine.create(containerConfig)
        print(container.id)
    }
}
