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

        // Detach by default (we track state)
        args += ["-d"]

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

        if container.state == .running && !force {
            throw MockerError.operationFailed(
                "You cannot remove a running container \(container.id). Stop the container before attempting removal or use -f"
            )
        }

        if container.state == .running {
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
        return containers.map { ($0, ContainerStats()) }
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
                name: (cfg["hostname"] as? String) ?? name,
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
    public var cpuPercent: Double = 0
    public var memUsage: UInt64 = 0
    public var memLimit: UInt64 = 0
    public var netIn: UInt64 = 0
    public var netOut: UInt64 = 0
    public var blockIn: UInt64 = 0
    public var blockOut: UInt64 = 0
    public var pids: Int = 0
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
