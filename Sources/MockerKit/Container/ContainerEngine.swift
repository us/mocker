import Foundation

/// Manages the lifecycle of containers using Apple's Containerization framework.
public actor ContainerEngine {
    private let config: MockerConfig
    private let store: ContainerStore

    public init(config: MockerConfig = MockerConfig()) throws {
        self.config = config
        self.store = try ContainerStore(path: config.containersPath)
    }

    // MARK: - Container Lifecycle

    /// Create and optionally start a container.
    public func run(_ containerConfig: ContainerConfig) async throws -> ContainerInfo {
        let id = generateID()
        let name = containerConfig.name ?? generateName()

        // Check for name conflicts
        if let existing = try await store.findByName(name) {
            throw MockerError.containerAlreadyExists(existing.name)
        }

        let info = ContainerInfo(
            id: id,
            name: name,
            image: containerConfig.image,
            state: .created,
            status: "Created",
            created: Date(),
            ports: containerConfig.ports,
            labels: containerConfig.labels,
            command: containerConfig.command.joined(separator: " ")
        )

        try await store.save(info)

        // TODO: Use Containerization framework to actually create and start the container
        // For now, we simulate the state transition
        var running = info
        running.state = .running
        running.status = "Up Less than a second"
        try await store.save(running)

        return running
    }

    /// List containers, optionally including stopped ones.
    public func list(all: Bool = false) async throws -> [ContainerInfo] {
        let containers = try await store.listAll()
        if all {
            return containers
        }
        return containers.filter { $0.state.isActive }
    }

    /// Stop a running container.
    public func stop(_ identifier: String) async throws -> ContainerInfo {
        var container = try await resolve(identifier)
        guard container.state == .running else {
            throw MockerError.containerNotRunning(identifier)
        }

        // TODO: Use Containerization framework to stop the container
        container.state = .exited
        container.status = "Exited (0)"
        try await store.save(container)
        return container
    }

    /// Remove a container.
    public func remove(_ identifier: String, force: Bool = false) async throws -> ContainerInfo {
        let container = try await resolve(identifier)

        if container.state == .running && !force {
            throw MockerError.operationFailed(
                "You cannot remove a running container \(container.id). Stop the container before attempting removal or use -f"
            )
        }

        if container.state == .running {
            _ = try await stop(identifier)
        }

        try await store.delete(container.id)
        return container
    }

    /// Get logs for a container.
    public func logs(_ identifier: String, follow: Bool = false, tail: Int? = nil) async throws -> [String] {
        let container = try await resolve(identifier)

        // TODO: Use Containerization framework to stream actual logs
        return [
            "[\(container.name)] Container started",
            "[\(container.name)] Listening on port 80",
        ]
    }

    /// Execute a command inside a running container.
    public func exec(_ identifier: String, command: [String], interactive: Bool = false, tty: Bool = false) async throws {
        let container = try await resolve(identifier)
        guard container.state == .running else {
            throw MockerError.containerNotRunning(identifier)
        }

        // TODO: Use Containerization framework to exec into container
        print("Executing \(command.joined(separator: " ")) in container \(container.name)")
    }

    /// Inspect a container and return detailed JSON-serializable info.
    public func inspect(_ identifier: String) async throws -> ContainerInfo {
        try await resolve(identifier)
    }

    // MARK: - Private Helpers

    /// Resolve an identifier (name or ID prefix) to a container.
    private func resolve(_ identifier: String) async throws -> ContainerInfo {
        if let container = try await store.findByName(identifier) {
            return container
        }
        if let container = try await store.findByIDPrefix(identifier) {
            return container
        }
        throw MockerError.containerNotFound(identifier)
    }

    private func generateID() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func generateName() -> String {
        let adjectives = ["brave", "calm", "eager", "fancy", "happy", "jolly", "kind", "lively", "nice", "proud"]
        let nouns = ["alpine", "bay", "cedar", "dawn", "elm", "frost", "grove", "hill", "iris", "jade"]
        let adj = adjectives.randomElement()!
        let noun = nouns.randomElement()!
        return "\(adj)_\(noun)"
    }
}
