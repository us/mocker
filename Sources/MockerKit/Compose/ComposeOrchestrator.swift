import Foundation

/// Progress events emitted during compose operations.
public enum ComposeEvent: Sendable {
    case networkCreated(String)
    case volumeCreated(String)
    case containerCreated(String)
    case containerStarted(String)
    case containerStopped(String)
    case containerRemoved(String)
    case networkRemoved(String)
}

/// Orchestrates multi-container deployments from a compose file.
public actor ComposeOrchestrator {
    private let engine: ContainerEngine
    private let imageManager: ImageManager
    private let networkManager: NetworkManager
    private let volumeManager: VolumeManager
    private let projectName: String

    public init(
        projectName: String,
        engine: ContainerEngine,
        imageManager: ImageManager,
        networkManager: NetworkManager,
        volumeManager: VolumeManager
    ) {
        self.projectName = projectName
        self.engine = engine
        self.imageManager = imageManager
        self.networkManager = networkManager
        self.volumeManager = volumeManager
    }

    /// Start all services defined in a compose file.
    public func up(composeFile: ComposeFile, detach: Bool = false) async throws -> [ComposeEvent] {
        var events: [ComposeEvent] = []

        // Create networks
        for (name, net) in composeFile.networks.sorted(by: { $0.key < $1.key }) {
            let fullName = "\(projectName)-\(name)"
            if (try? await networkManager.create(name: fullName, driver: net.driver)) != nil {
                events.append(.networkCreated(fullName))
            }
        }

        // Create volumes
        for (name, vol) in composeFile.volumes.sorted(by: { $0.key < $1.key }) {
            let fullName = "\(projectName)-\(name)"
            if (try? await volumeManager.create(name: fullName, driver: vol.driver)) != nil {
                events.append(.volumeCreated(fullName))
            }
        }

        // Start services in dependency order
        let order = composeFile.serviceOrder()
        for serviceName in order {
            guard let service = composeFile.services[serviceName] else { continue }
            try await startService(service, detach: detach)
            let containerName = "\(projectName)-\(service.name)-1"
            events.append(.containerStarted(containerName))
        }

        return events
    }

    /// Stop and remove all services.
    public func down(composeFile: ComposeFile) async throws -> [ComposeEvent] {
        var events: [ComposeEvent] = []
        let containers = try await engine.list(all: true)
        let prefix = "\(projectName)-"

        for container in containers where container.name.hasPrefix(prefix) {
            if container.state.isActive {
                _ = try await engine.stop(container.id)
                events.append(.containerStopped(container.name))
            }
            _ = try await engine.remove(container.id)
            events.append(.containerRemoved(container.name))
        }

        // Remove networks
        for (name, _) in composeFile.networks.sorted(by: { $0.key < $1.key }) {
            let fullName = "\(projectName)-\(name)"
            if (try? await networkManager.remove(fullName)) != nil {
                events.append(.networkRemoved(fullName))
            }
        }

        return events
    }

    /// List services and their status.
    public func ps() async throws -> [ContainerInfo] {
        let containers = try await engine.list(all: true)
        let prefix = "\(projectName)-"
        return containers.filter { $0.name.hasPrefix(prefix) }
    }

    /// Restart a specific service or all services.
    public func restart(composeFile: ComposeFile, service: String? = nil) async throws -> [ComposeEvent] {
        var events: [ComposeEvent] = []
        let containers = try await ps()
        let targets: [ContainerInfo]

        if let service {
            let fullName = "\(projectName)-\(service)"
            targets = containers.filter { $0.name.hasPrefix(fullName) }
        } else {
            targets = containers
        }

        // Stop and remove targets
        for container in targets {
            if container.state.isActive {
                _ = try await engine.stop(container.id)
                events.append(.containerStopped(container.name))
            }
            _ = try await engine.remove(container.id)
            events.append(.containerRemoved(container.name))
        }

        // Recreate services
        if let service, let svc = composeFile.services[service] {
            try await startService(svc, detach: true)
            events.append(.containerStarted("\(projectName)-\(service)-1"))
        } else {
            for serviceName in composeFile.serviceOrder() {
                guard let svc = composeFile.services[serviceName] else { continue }
                try await startService(svc, detach: true)
                events.append(.containerStarted("\(projectName)-\(serviceName)-1"))
            }
        }

        return events
    }

    // MARK: - Private

    private func startService(_ service: ComposeService, detach: Bool) async throws {
        let containerName = "\(projectName)-\(service.name)-1"

        // Pull or build image
        if let image = service.image {
            _ = try await imageManager.pull(image)
        } else if let build = service.build {
            let tag = "\(projectName)-\(service.name):latest"
            _ = try await imageManager.build(
                tag: tag,
                context: build.context,
                dockerfile: build.dockerfile ?? "Dockerfile"
            )
        }

        let imageName = service.image ?? "\(projectName)-\(service.name):latest"

        // Parse port mappings
        let ports = try service.ports.map { try PortMapping.parse($0) }
        let volumes = try service.volumes.map { try VolumeMount.parse($0) }

        let config = ContainerConfig(
            name: containerName,
            image: imageName,
            command: service.command,
            environment: service.environment,
            ports: ports,
            volumes: volumes,
            network: service.networks.first.map { "\(projectName)-\($0)" },
            detach: detach,
            labels: service.labels.merging(
                ["com.mocker.compose.project": projectName, "com.mocker.compose.service": service.name]
            ) { _, new in new },
            workingDir: service.workingDir,
            hostname: service.hostname
        )

        _ = try await engine.run(config)
    }
}
