import Foundation

/// Progress events emitted during compose operations.
public enum ComposeEvent: Sendable {
    case networkCreated(String)
    case volumeCreated(String)
    case containerCreated(String)
    case containerStarted(String)
    case containerRunning(String)
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
    private let projectDir: URL

    public init(
        projectName: String,
        projectDir: URL,
        engine: ContainerEngine,
        imageManager: ImageManager,
        networkManager: NetworkManager,
        volumeManager: VolumeManager
    ) {
        self.projectName = projectName
        self.projectDir = projectDir
        self.engine = engine
        self.imageManager = imageManager
        self.networkManager = networkManager
        self.volumeManager = volumeManager
    }

    /// Start all services defined in a compose file.
    /// - Parameters:
    ///   - build: force-build images even if they already exist (compose `--build`).
    ///   - noBuild: never build, pull `image:` instead (compose `--no-build`).
    ///   - forceRecreate: recreate every project container regardless of hash
    ///     (compose `--force-recreate`).
    ///   - noRecreate: never recreate existing project containers (compose `--no-recreate`).
    public func up(
        composeFile: ComposeFile,
        detach: Bool = false,
        build: Bool = false,
        noBuild: Bool = false,
        forceRecreate: Bool = false,
        noRecreate: Bool = false
    ) async throws -> [ComposeEvent] {
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

        let prefix = "\(projectName)-"
        let observed = (try? await engine.list(all: true))?
            .filter { $0.name.hasPrefix(prefix) }
            .map { container -> ObservedContainer in
                ObservedContainer(
                    name: container.name,
                    serviceName: container.labels["com.mocker.compose.service"] ?? "",
                    configHash: container.labels["com.mocker.compose.config-hash"]
                )
            } ?? []
        let actions = Self.reconcileDecision(
            observedContainers: observed,
            composeFile: composeFile,
            projectName: projectName,
            forceRecreate: forceRecreate,
            noRecreate: noRecreate
        )
        var skipSet: Set<String> = []
        for action in actions {
            switch action.kind {
            case .keep:
                skipSet.insert(action.serviceName)
                events.append(.containerRunning("\(projectName)-\(action.serviceName)-1"))
            case .removeAndRecreate:
                if let existing = observed.first(where: { $0.serviceName == action.serviceName }) {
                    if let live = (try? await engine.list(all: true))?.first(where: { $0.name == existing.name }),
                       live.state.isActive {
                        _ = try? await engine.stop(live.id)
                        events.append(.containerStopped(live.name))
                    }
                    _ = try? await engine.remove(existing.name, force: true)
                    events.append(.containerRemoved(existing.name))
                }
            case .noOp:
                break
            }
        }

        // Start services in dependency order
        let order = composeFile.serviceOrder()
        var startedContainers: [(serviceName: String, info: ContainerInfo)] = []

        for serviceName in order where !skipSet.contains(serviceName) {
            guard let service = composeFile.services[serviceName] else { continue }
            let info = try await startService(service, detach: detach, forceBuild: build, noBuild: noBuild)
            let containerName = "\(projectName)-\(service.name)-1"
            startedContainers.append((serviceName: serviceName, info: info))
            events.append(.containerStarted(containerName))
        }

        // Inject inter-service hostnames into /etc/hosts of each container.
        // All containers share the same vmnet subnet and can reach each other by IP.
        // We add /etc/hosts entries so service names resolve (e.g. "db" → 192.168.64.6).
        await injectServiceHostnames(startedContainers)

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
        var restarted: [(serviceName: String, info: ContainerInfo)] = []
        if let service, let svc = composeFile.services[service] {
            let info = try await startService(svc, detach: true)
            restarted.append((serviceName: service, info: info))
            events.append(.containerStarted("\(projectName)-\(service)-1"))
        } else {
            for serviceName in composeFile.serviceOrder() {
                guard let svc = composeFile.services[serviceName] else { continue }
                let info = try await startService(svc, detach: true)
                restarted.append((serviceName: serviceName, info: info))
                events.append(.containerStarted("\(projectName)-\(serviceName)-1"))
            }
        }
        await injectServiceHostnames(restarted)

        return events
    }

    // MARK: - Private

    /// Inject other services' IPs into /etc/hosts of each running container.
    /// This enables service-name DNS resolution (e.g. "db:5432") in compose projects.
    private func injectServiceHostnames(_ containers: [(serviceName: String, info: ContainerInfo)]) async {
        // Only containers with a known IP can participate
        let withIP = containers.filter { !$0.info.networkAddress.isEmpty }
        guard withIP.count > 1 else { return }

        for target in withIP {
            // Build /etc/hosts entries for all *other* services
            let otherServices = withIP.filter { $0.serviceName != target.serviceName }
            guard !otherServices.isEmpty else { continue }

            // Build args array for safe execution — no shell interpolation
            // Each entry is passed as a separate argument to avoid injection
            var hostsContent = ""
            for svc in otherServices {
                hostsContent += "\(svc.info.networkAddress) \(svc.serviceName)\n"
            }

            // Use tee -a to append to /etc/hosts without shell interpolation
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CLIResolver.resolve())
            process.arguments = ["exec", "-i", target.info.id, "tee", "-a", "--", "/etc/hosts"]
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                inputPipe.fileHandleForWriting.write(Data(hostsContent.utf8))
                inputPipe.fileHandleForWriting.closeFile()
                // Async-safe: use terminationHandler instead of blocking waitUntilExit
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    process.terminationHandler = { _ in
                        continuation.resume()
                    }
                }
            } catch {
                // Silently ignore if container doesn't support exec (e.g. no tee)
            }
        }
    }

    private func startService(
        _ service: ComposeService,
        detach: Bool,
        forceBuild: Bool = false,
        noBuild: Bool = false
    ) async throws -> ContainerInfo {
        let containerName = "\(projectName)-\(service.name)-1"

        // Decide whether to build or pull. Per the Compose spec, a service with
        // both `image:` and `build:` is built and tagged with `image:` — not pulled.
        switch service.resolveImageSource(projectName: projectName, noBuild: noBuild) {
        case .pull(let image):
            _ = try await imageManager.pull(image)
        case .build(let tag, let build):
            // Skip the rebuild only when `--build` wasn't requested and the image exists.
            var shouldBuild = forceBuild
            if !shouldBuild {
                let existingImages = try await imageManager.list()
                shouldBuild = !existingImages.contains { ComposeService.imageMatches($0, tag: tag) }
            }
            if shouldBuild {
                let absContext = ImageManager.resolveContextPath(context: build.context, cwd: projectDir.path)
                let dockerfilePath = ImageManager.composeDockerfilePath(
                    context: absContext,
                    dockerfile: build.dockerfile ?? "Dockerfile",
                    cwd: projectDir.path
                )
                _ = try await imageManager.build(
                    tag: tag,
                    context: absContext,
                    dockerfile: dockerfilePath,
                    buildArgs: build.argList,
                    target: build.target
                )
            }
        case .none:
            break
        }

        let imageName = service.image ?? "\(projectName)-\(service.name):latest"

        // Parse port mappings
        let ports = try service.ports.map { try PortMapping.parse($0) }

        let volumes = try Self.resolveVolumeMounts(service.volumes)

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
                [
                    "com.mocker.compose.project": projectName,
                    "com.mocker.compose.service": service.name,
                    "com.mocker.compose.config-hash": ComposeService.hash(of: service),
                ]
            ) { _, new in new },
            workingDir: service.workingDir,
            hostname: service.hostname,
            // `restartPolicy` and `shmSize` (like the soft mem/cpu reservations) are stored on the
            // config for Docker surface parity, mirroring `run`/`create`. Apple's `container` CLI
            // currently exposes no `--restart`/`--shm-size` flags, so these are NOT enforced by the
            // runtime today — only `memory` (-m) and `cpus` (-c) are actually emitted.
            restartPolicy: service.restart.flatMap { RestartPolicy(rawValue: $0) } ?? .no,
            shmSize: service.shmSize,
            memory: service.memLimit,
            cpus: service.cpus
        )

        return try await engine.run(config)
    }

    /// Resolve volume spec strings from a compose service into `VolumeMount` values.
    ///
    /// Bind-mount host paths (absolute or relative) are included; anonymous volumes
    /// (container paths only) are included; named volumes (bare names without path
    /// separators) are skipped — Apple's virtiofs doesn't support chown from within
    /// containers, which breaks images like postgres that chown their data directory
    /// on init.
    ///
    /// Relative paths (`./foo`, `../bar`, `data/dir`) are resolved to absolute paths
    /// against the current working directory. This matches Docker Compose behaviour
    /// because `mocker compose` is run from the project directory.
    static func resolveVolumeMounts(_ volSpecs: [String]) throws -> [VolumeMount] {
        var volumes: [VolumeMount] = []
        for volSpec in volSpecs {
            var mount = try VolumeMount.parse(volSpec)
            if mount.source.isEmpty {
                volumes.append(mount)
            } else if mount.source.hasPrefix("/") {
                volumes.append(mount)
            } else if mount.source.hasPrefix(".")
                      || mount.source.hasPrefix("~")
                      || mount.source.contains("/") {
                mount.source = URL(fileURLWithPath: mount.source).path
                volumes.append(mount)
            }
        }
        return volumes
    }
}
extension ComposeOrchestrator {
    /// Pure helper that returns one `ReconcileAction` per service in the project.
    /// Mirrors Docker's `mustRecreate` at `pkg/compose/reconcile.go:517-543`.
    public nonisolated static func reconcileDecision(
        observedContainers: [ObservedContainer],
        composeFile: ComposeFile,
        projectName: String,
        forceRecreate: Bool,
        noRecreate: Bool
    ) -> [ReconcileAction] {
        composeFile.serviceOrder().compactMap { serviceName -> ReconcileAction? in
            guard let service = composeFile.services[serviceName] else { return nil }
            let observed = observedContainers.first { $0.serviceName == serviceName }
            let kind: ReconcileAction.Kind
            switch (observed, forceRecreate, noRecreate) {
            case (.none, _, _):
                kind = .noOp
            case (_, true, _):
                kind = .removeAndRecreate
            case (_, _, true):
                kind = .keep
            case (let .some(obs), false, false):
                let expectedHash = ComposeService.hash(of: service)
                if obs.configHash != expectedHash {
                    kind = .removeAndRecreate
                } else if let digest = obs.imageDigest, digest != service.image {
                    kind = .removeAndRecreate
                } else {
                    kind = .keep
                }
            }
            return ReconcileAction(serviceName: serviceName, kind: kind)
        }
    }
}

/// Snapshot of a project container as observed by `engine.list(all: true)`, scoped to
/// the per-service decision inputs (`configHash`, `imageDigest`, `serviceName`).
public struct ObservedContainer: Sendable, Equatable {
    public let name: String
    public let serviceName: String
    public let configHash: String?
    public let imageDigest: String?
    public let state: ContainerState

    public init(
        name: String,
        serviceName: String,
        configHash: String? = nil,
        imageDigest: String? = nil,
        state: ContainerState = .running
    ) {
        self.name = name
        self.serviceName = serviceName
        self.configHash = configHash
        self.imageDigest = imageDigest
        self.state = state
    }
}

/// Per-service action emitted by `ComposeOrchestrator.reconcileDecision`.
public struct ReconcileAction: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case keep
        case removeAndRecreate
        case noOp
    }

    public let serviceName: String
    public let kind: Kind

    public init(serviceName: String, kind: Kind) {
        self.serviceName = serviceName
        self.kind = kind
    }
}
