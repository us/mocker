import Foundation

/// Manages container lifecycle by delegating to Apple's `container` CLI.
/// Image operations use Containerization.ImageStore directly.
/// Container lifecycle uses `container` CLI subprocess (which has the required
/// com.apple.security.virtualization entitlement via its own signing).
///
/// Note: Direct `LinuxContainer`/`ContainerManager` integration was attempted but requires
/// a vminit image that matches the open-source framework version (0.26.x). Apple's public
/// container CLI uses vminit:0.1.0 which is incompatible with the main branch framework.
/// See PROGRESS.md for details.
public actor ContainerEngine {
    private let config: MockerConfig
    private let store: ContainerStore
    private let portProxy: PortProxy

    private static let containerCLI = "/usr/local/bin/container"

    public init(config: MockerConfig = MockerConfig()) throws {
        self.config = config
        self.store = try ContainerStore(path: config.containersPath)
        self.portProxy = PortProxy(proxiesDir: config.proxiesPath)
    }

    // MARK: - Create (without starting)

    public func create(_ containerConfig: ContainerConfig) async throws -> ContainerInfo {
        // Apple's container CLI does not support create-without-start.
        throw MockerError.operationFailed(
            "container create is not supported by Apple Containerization runtime. Use 'mocker run' instead."
        )
    }

    // MARK: - Run

    public func run(_ containerConfig: ContainerConfig) async throws -> ContainerInfo {
        let name = containerConfig.name ?? generateName()

        // Check for name conflicts in our store
        if let existing = try await store.findByName(name) {
            throw MockerError.containerAlreadyExists(existing.name)
        }

        // Build `container run` arguments
        var args = ["run"]

        args += ["--name", name]

        for env in containerConfig.environment {
            args += ["-e", "\(env.key)=\(env.value)"]
        }

        for vol in containerConfig.volumes {
            if !vol.source.isEmpty {
                args += ["-v", "\(vol.source):\(vol.destination)\(vol.readOnly ? ":ro" : "")"]
            }
        }

        if let workingDir = containerConfig.workingDir, !workingDir.isEmpty {
            args += ["-w", workingDir]
        }

        if let user = containerConfig.user, !user.isEmpty {
            args += ["--user", user]
        }

        if let entrypoint = containerConfig.entrypoint, !entrypoint.isEmpty {
            args += ["--entrypoint", entrypoint]
        }

        for d in containerConfig.dns {
            args += ["--dns", d]
        }

        for host in containerConfig.addHost {
            args += ["--add-host", host]
        }

        // Apple CLI supported flags
        if let hostname = containerConfig.hostname, !hostname.isEmpty {
            // Note: Apple CLI uses --name for hostname — we pass a separate --name above
            // hostname is stored in metadata only; Apple CLI doesn't have a --hostname flag
        }

        for label in containerConfig.labels {
            args += ["-l", "\(label.key)=\(label.value)"]
        }

        if let cidfile = containerConfig.cidfile, !cidfile.isEmpty {
            args += ["--cidfile", cidfile]
        }

        if containerConfig.interactive { args.append("-i") }
        if containerConfig.tty { args.append("-t") }

        if let cpus = containerConfig.cpus {
            args += ["-c", String(cpus)]
        }

        if let memory = containerConfig.memory {
            args += ["-m", memory]
        }

        for t in containerConfig.tmpfs {
            args += ["--tmpfs", t]
        }

        if containerConfig.rm { args.append("--rm") }

        for dnsSearch in containerConfig.dnsSearch {
            args += ["--dns-search", dnsSearch]
        }

        for dnsOpt in containerConfig.dnsOption {
            args += ["--dns-option", dnsOpt]
        }

        if let platform = containerConfig.platform, !platform.isEmpty {
            let parts = platform.split(separator: "/")
            if parts.count >= 1 { args += ["--os", String(parts[0])] }
            if parts.count >= 2 { args += ["--arch", String(parts[1])] }
        }

        // Detach by default unless interactive
        if !containerConfig.interactive {
            args += ["-d"]
        }

        args.append(containerConfig.image)
        args += containerConfig.command

        let (output, exitCode) = try await runCLI(args)

        guard exitCode == 0 else {
            let msg = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MockerError.operationFailed(msg.isEmpty ? "container run failed" : msg)
        }

        // output is the container ID/name
        let assignedID = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fetch real state from the container CLI
        let info = try await fetchContainerInfo(id: assignedID, name: name, config: containerConfig)
        try await store.save(info)

        // Start port proxies if -p mappings were requested and we got an IP
        if !containerConfig.ports.isEmpty, !info.networkAddress.isEmpty {
            try? await portProxy.start(
                containerID: info.id,
                ports: containerConfig.ports,
                containerIP: info.networkAddress
            )
        }

        return info
    }

    // MARK: - List

    public func list(all: Bool = false) async throws -> [ContainerInfo] {
        // Get live state from container CLI
        let (output, _) = try await runCLI(["ls"])
        let liveIDs = parseLSOutput(output)

        var containers = try await store.listAll()

        // Update state for each container we're tracking
        for i in containers.indices {
            let c = containers[i]
            if liveIDs.contains(c.name) || liveIDs.contains(c.id) {
                containers[i].state = .running
                containers[i].status = "Up"
            } else if containers[i].state == .running {
                containers[i].state = .exited
                containers[i].status = "Exited (0)"
                try await store.save(containers[i])
            }
        }

        if all {
            return containers
        }
        return containers.filter { $0.state.isActive }
    }

    // MARK: - Stop

    public func stop(_ identifier: String) async throws -> ContainerInfo {
        let container = try await resolve(identifier)
        guard container.state == .running else {
            throw MockerError.containerNotRunning(identifier)
        }

        let (_, exitCode) = try await runCLI(["stop", container.name])
        guard exitCode == 0 else {
            throw MockerError.operationFailed("failed to stop container \(container.name)")
        }

        await portProxy.stop(containerID: container.id)

        var updated = container
        updated.state = .exited
        updated.status = "Exited (0)"
        try await store.save(updated)
        return updated
    }

    // MARK: - Remove

    public func remove(_ identifier: String, force: Bool = false) async throws -> ContainerInfo {
        let container = try await resolve(identifier)

        // Check live state — store may be stale (e.g. container exited on its own)
        let (lsOut, _) = (try? await runCLI(["ls"])) ?? ("", 0)
        let liveIDs = parseLSOutput(lsOut)
        let isLiveRunning = liveIDs.contains(container.name) || liveIDs.contains(container.id)

        if isLiveRunning && !force {
            throw MockerError.operationFailed(
                "You cannot remove a running container \(container.id). Stop the container before attempting removal or use -f"
            )
        }

        if isLiveRunning {
            _ = try? await runCLI(["stop", container.name])
        }

        await portProxy.stop(containerID: container.id)

        _ = try? await runCLI(["delete", container.name])
        try await store.delete(container.id)
        return container
    }

    // MARK: - Logs

    public func logs(_ identifier: String, follow: Bool = false, tail: Int? = nil) async throws -> [String] {
        let container = try await resolve(identifier)
        var args = ["logs", container.name]
        if follow { args.append("-f") }

        let (output, _) = try await runCLI(args)
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    // MARK: - Exec

    public func exec(_ identifier: String, command: [String], interactive: Bool = false, tty: Bool = false) async throws {
        let container = try await resolve(identifier)
        guard container.state == .running else {
            throw MockerError.containerNotRunning(identifier)
        }

        var args = ["exec"]
        if interactive { args.append("-i") }
        if tty { args.append("-t") }
        args.append(container.name)
        args += command

        let (output, exitCode) = try await runCLI(args)
        if !output.isEmpty { print(output) }
        if exitCode != 0 {
            throw MockerError.operationFailed("exec failed with exit code \(exitCode)")
        }
    }

    // MARK: - Inspect

    public func inspect(_ identifier: String) async throws -> ContainerInfo {
        try await resolve(identifier)
    }

    // MARK: - Stats

    public func stats(containerIDs: [String]) async throws -> [(ContainerInfo, ContainerStats)] {
        let containers: [ContainerInfo]
        if containerIDs.isEmpty {
            containers = try await list(all: false)
        } else {
            var resolved: [ContainerInfo] = []
            for id in containerIDs { try await resolved.append(resolve(id)) }
            containers = resolved
        }
        var results: [(ContainerInfo, ContainerStats)] = []
        for c in containers {
            let s = await fetchContainerStats(c)
            results.append((c, s))
        }
        return results
    }

    private func fetchContainerStats(_ container: ContainerInfo) async -> ContainerStats {
        // Single ps call with full command line
        guard let (psOut, _) = try? await runProcess("/bin/ps", ["ax", "-o", "pid,pcpu,rss,command"]) else {
            return ContainerStats()
        }

        struct VMProc { var pid: Int32; var cpu: Double; var rss: UInt64 }
        var thisRuntimePID: Int32? = nil
        var allRuntimePIDs: [Int32] = []
        var allVMProcs: [VMProc] = []

        for line in psOut.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 4, let pid = Int32(parts[0]) else { continue }
            let cpu = Double(parts[1]) ?? 0
            let rss = (UInt64(parts[2]) ?? 0) * 1024
            let cmd = parts[3...].joined(separator: " ")

            if cmd.contains("container-runtime-linux") {
                allRuntimePIDs.append(pid)
                if cmd.contains("--uuid \(container.name)") { thisRuntimePID = pid }
            } else if cmd.contains("Virtualization.VirtualMachine") {
                allVMProcs.append(VMProc(pid: pid, cpu: cpu, rss: rss))
            }
        }

        guard let runtimePID = thisRuntimePID else { return ContainerStats() }

        // Match runtimes → VMs by sorted PID position.
        // VMs are XPC services (PPID=1) so we can't use parent PID.
        // Instead: sort both by PID, filter VMs with PID > min(runtime PID),
        // then pair by index (1st runtime ↔ 1st VM, etc.)
        let sortedRuntimes = allRuntimePIDs.sorted()
        let minRuntime = sortedRuntimes.min() ?? 0
        let sortedVMs = allVMProcs.filter { $0.pid > minRuntime }.sorted { $0.pid < $1.pid }

        guard let runtimeIndex = sortedRuntimes.firstIndex(of: runtimePID),
              runtimeIndex < sortedVMs.count else { return ContainerStats() }

        let vm = sortedVMs[runtimeIndex]

        // Memory limit from container inspect
        var memLimit: UInt64 = 1_073_741_824 // 1 GB default
        if let (inspectOut, _) = try? await runCLI(["inspect", container.name]),
           let data = inspectOut.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = arr.first,
           let cfg = first["configuration"] as? [String: Any],
           let resources = cfg["resources"] as? [String: Any],
           let mem = resources["memoryInBytes"] as? Int {
            memLimit = UInt64(mem)
        }

        return ContainerStats(cpuPercent: vm.cpu, memUsage: vm.rss, memLimit: memLimit)
    }

    @discardableResult
    private func runProcess(_ path: String, _ arguments: [String]) async throws -> (String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        // Read on a background thread to drain the pipe continuously,
        // preventing pipe-buffer deadlock with large output.
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let out = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (out, process.terminationStatus))
            }
        }
    }

    // MARK: - Rename

    public func rename(_ identifier: String, to newName: String) async throws {
        // Apple Containerization does not support container rename
        throw MockerError.operationFailed(
            "container rename is not supported by Apple Containerization runtime"
        )
    }

    // MARK: - Copy

    public func copyFromContainer(_ identifier: String, path: String) async throws -> Data {
        let container = try await resolve(identifier)
        let (output, exitCode) = try await runCLI(["exec", container.name, "cat", path])
        guard exitCode == 0 else {
            throw MockerError.operationFailed("failed to read \(path) from container \(identifier)")
        }
        return Data(output.utf8)
    }

    public func copyToContainer(_ identifier: String, path: String, data: Data) async throws {
        let container = try await resolve(identifier)
        // Write data via stdin pipe to tee — avoids shell interpolation (injection-safe)
        let content = String(data: data, encoding: .utf8) ?? ""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/container")
        process.arguments = ["exec", "-i", container.name, "tee", "--", path]
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        // Discard tee stdout (it echoes input) — use /dev/null to avoid pipe-buffer hang
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        inputPipe.fileHandleForWriting.write(Data(content.utf8))
        inputPipe.fileHandleForWriting.closeFile()
        // Use async-safe termination handler instead of blocking waitUntilExit
        let exitCode = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { p in
                continuation.resume(returning: p.terminationStatus)
            }
        }
        guard exitCode == 0 else {
            throw MockerError.operationFailed("failed to write to \(path) in container \(identifier)")
        }
    }

    // MARK: - Top

    public func top(_ identifier: String, psArgs: [String] = ["-ef"]) async throws -> String {
        let container = try await resolve(identifier)
        guard container.state == .running else {
            throw MockerError.containerNotRunning(identifier)
        }
        var args = ["exec", container.name, "ps"]
        args += psArgs
        let (output, _) = try await runCLI(args)
        return output
    }

    // MARK: - Diff

    public func diff(_ identifier: String) async throws -> [String] {
        let container = try await resolve(identifier)
        // Use exec to find modified files - simplified implementation
        let (output, _) = try await runCLI(["exec", container.name, "find", "/", "-newer", "/proc", "-not", "-path", "/proc/*", "-not", "-path", "/sys/*"])
        return output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map { "C \($0)" }
    }

    // MARK: - Pause / Unpause

    public func pause(_ identifier: String) async throws {
        _ = try await resolve(identifier)
        // Apple Containerization does not support pause/unpause
        throw MockerError.operationFailed(
            "container pause is not supported by Apple Containerization runtime"
        )
    }

    public func unpause(_ identifier: String) async throws {
        _ = try await resolve(identifier)
        // Apple Containerization does not support pause/unpause
        throw MockerError.operationFailed(
            "container unpause is not supported by Apple Containerization runtime"
        )
    }

    // MARK: - Start (stopped container)

    public func start(_ identifier: String) async throws -> ContainerInfo {
        let container = try await resolve(identifier)
        guard container.state != .running else { return container }

        let (_, exitCode) = try await runCLI(["start", container.name])
        guard exitCode == 0 else {
            throw MockerError.operationFailed("failed to start container \(container.name)")
        }

        var updated = container
        updated.state = .running
        updated.status = "Up"
        try await store.save(updated)
        return updated
    }

    // MARK: - Private Helpers

    private func resolve(_ identifier: String) async throws -> ContainerInfo {
        if let container = try await store.findByName(identifier) { return container }
        if let container = try await store.findByIDPrefix(identifier) { return container }
        throw MockerError.containerNotFound(identifier)
    }

    private func fetchContainerInfo(id: String, name: String, config: ContainerConfig) async throws -> ContainerInfo {
        let (output, _) = try await runCLI(["inspect", name])

        // Parse JSON from container inspect
        if let data = output.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = arr.first,
           let cfg = first["configuration"] as? [String: Any] {
            let status = first["status"] as? String ?? "running"
            let networks = first["networks"] as? [[String: Any]] ?? []
            let addr = networks.first?["address"] as? String ?? ""

            return ContainerInfo(
                id: (cfg["id"] as? String) ?? id,
                name: name,  // Use our assigned name, not hostname from inspect
                image: config.image,
                state: status == "running" ? .running : .exited,
                status: status == "running" ? "Up Less than a second" : "Exited (0)",
                created: Date(),
                ports: config.ports,
                labels: config.labels,
                command: config.command.joined(separator: " "),
                networkAddress: addr
            )
        }

        // Fallback if inspect fails
        return ContainerInfo(
            id: id,
            name: name,
            image: config.image,
            state: .running,
            status: "Up Less than a second",
            created: Date(),
            ports: config.ports,
            labels: config.labels,
            command: config.command.joined(separator: " "),
            networkAddress: ""
        )
    }

    private func parseLSOutput(_ output: String) -> Set<String> {
        var ids = Set<String>()
        let lines = output.components(separatedBy: "\n").dropFirst() // skip header
        for line in lines {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            if let id = cols.first.map(String.init) {
                ids.insert(id)
            }
        }
        return ids
    }

    @discardableResult
    private func runCLI(_ arguments: [String]) async throws -> (String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.containerCLI)
        process.arguments = arguments

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        try process.run()

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { p in
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let combined = out.isEmpty ? err : out
                continuation.resume(returning: (combined, p.terminationStatus))
            }
        }
    }

    private func generateID() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func generateName() -> String {
        let adjectives = ["brave", "calm", "eager", "fancy", "happy", "jolly", "kind", "lively", "nice", "proud"]
        let nouns = ["alpine", "bay", "cedar", "dawn", "elm", "frost", "grove", "hill", "iris", "jade"]
        return "\(adjectives.randomElement()!)_\(nouns.randomElement()!)"
    }
}

// MARK: - Supporting types

public struct ContainerStats: Sendable {
    public var cpuPercent: Double
    public var memUsage: UInt64
    public var memLimit: UInt64
    public var netIn: UInt64
    public var netOut: UInt64
    public var blockIn: UInt64
    public var blockOut: UInt64
    public var pids: Int

    public init(
        cpuPercent: Double = 0,
        memUsage: UInt64 = 0,
        memLimit: UInt64 = 0,
        netIn: UInt64 = 0,
        netOut: UInt64 = 0,
        blockIn: UInt64 = 0,
        blockOut: UInt64 = 0,
        pids: Int = 0
    ) {
        self.cpuPercent = cpuPercent
        self.memUsage = memUsage
        self.memLimit = memLimit
        self.netIn = netIn
        self.netOut = netOut
        self.blockIn = blockIn
        self.blockOut = blockOut
        self.pids = pids
    }
}

// MARK: - Async helpers

extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        for element in self {
            try await results.append(transform(element))
        }
        return results
    }
}
