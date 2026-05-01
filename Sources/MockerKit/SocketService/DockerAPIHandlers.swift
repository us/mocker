import Foundation

// MARK: - Docker Engine API Response Types

struct DockerVersionResponse: Encodable, Sendable {
    let Platform: PlatformName
    let Version: String
    let ApiVersion: String
    let MinAPIVersion: String
    let GitCommit: String
    let GoVersion: String
    let Os: String
    let Arch: String
    let KernelVersion: String
    let BuildTime: String

    struct PlatformName: Encodable, Sendable { let Name: String }
}

struct DockerInfoResponse: Encodable, Sendable {
    let ID: String
    let Containers: Int
    let ContainersRunning: Int
    let ContainersPaused: Int
    let ContainersStopped: Int
    let Images: Int
    let Driver: String
    let ServerVersion: String
    let OperatingSystem: String
    let OSType: String
    let Architecture: String
    let NCPU: Int
    let MemTotal: Int64
    let DockerRootDir: String
    let HttpProxy: String
    let HttpsProxy: String
    let NoProxy: String
    let Name: String
    let Labels: [String]
    let ExperimentalBuild: Bool
    let LiveRestoreEnabled: Bool
}

struct DockerContainerListItem: Encodable, Sendable {
    let Id: String
    let Names: [String]
    let Image: String
    let ImageID: String
    let Command: String
    let Created: Int64
    let State: String
    let Status: String
    let Ports: [DockerPort]
    let Labels: [String: String]
    let NetworkSettings: DockerNetworkSettings
    let Mounts: [DockerMount]
    let HostConfig: DockerHostConfig
}

struct DockerPort: Encodable, Sendable {
    let IP: String
    let PrivatePort: Int
    let PublicPort: Int
    let proto: String

    enum CodingKeys: String, CodingKey {
        case IP, PrivatePort, PublicPort
        case proto = "Type"
    }
}

struct DockerNetworkSettings: Encodable, Sendable {
    let Networks: [String: DockerNetwork]
}

struct DockerNetwork: Encodable, Sendable {
    let IPAddress: String
    let Gateway: String
    let MacAddress: String
}

struct DockerMount: Encodable, Sendable {
    let mountType: String
    let Source: String
    let Destination: String
    let Mode: String
    let RW: Bool

    enum CodingKeys: String, CodingKey {
        case mountType = "Type"
        case Source, Destination, Mode, RW
    }
}

struct DockerHostConfig: Encodable, Sendable {
    let NetworkMode: String
}

struct DockerContainerInspect: Encodable, Sendable {
    let Id: String
    let Created: String
    let Path: String
    let Args: [String]
    let State: DockerContainerState
    let Image: String
    let Name: String
    let Config: DockerContainerConfig
    let HostConfig: DockerInspectHostConfig
    let NetworkSettings: DockerInspectNetworkSettings
    let Mounts: [DockerMount]
}

struct DockerContainerState: Encodable, Sendable {
    let Status: String
    let Running: Bool
    let Paused: Bool
    let Restarting: Bool
    let Dead: Bool
    let Pid: Int
    let ExitCode: Int
    let Error: String
    let StartedAt: String
    let FinishedAt: String
}

struct DockerContainerConfig: Encodable, Sendable {
    let Hostname: String
    let Image: String
    let Labels: [String: String]
    let Cmd: [String]
    let Env: [String]
    let WorkingDir: String
    let Entrypoint: [String]?
}

struct DockerInspectHostConfig: Encodable, Sendable {
    let Binds: [String]
    let NetworkMode: String
    let PortBindings: [String: [DockerPortBinding]]
    let RestartPolicy: DockerRestartPolicy
    let Memory: Int64
    let CpuShares: Int
}

struct DockerPortBinding: Codable, Sendable {
    let HostIp: String
    let HostPort: String
}

struct DockerRestartPolicy: Encodable, Sendable {
    let Name: String
    let MaximumRetryCount: Int
}

struct DockerInspectNetworkSettings: Encodable, Sendable {
    let IPAddress: String
    let Networks: [String: DockerNetwork]
}

struct DockerImageListItem: Encodable, Sendable {
    let Id: String
    let RepoTags: [String]
    let RepoDigests: [String]
    let Created: Int64
    let Size: Int64
    let VirtualSize: Int64
    let Labels: [String: String]
}

struct DockerImageInspect: Encodable, Sendable {
    let Id: String
    let RepoTags: [String]
    let RepoDigests: [String]
    let Created: String
    let Size: Int64
    let VirtualSize: Int64
    let Labels: [String: String]
    let Architecture: String
    let Os: String
    let Config: DockerImageConfig
}

struct DockerImageConfig: Encodable, Sendable {
    let Cmd: [String]
    let Entrypoint: [String]?
    let Env: [String]
    let WorkingDir: String
    let Labels: [String: String]
}

struct DockerContainerCreateBody: Decodable, Sendable {
    let Image: String
    let Cmd: [String]?
    let Env: [String]?
    let Labels: [String: String]?
    let WorkingDir: String?
    let Entrypoint: [String]?
    let User: String?
    let HostConfig: CreateHostConfig?

    struct CreateHostConfig: Decodable, Sendable {
        let Binds: [String]?
        let PortBindings: [String: [DockerPortBinding]]?
        let Memory: Int64?
        let CpuShares: Int?
    }
}

// MARK: - Router

enum DockerAPIHandlers {
    static func route(
        request: HTTPRequest,
        engine: ContainerEngine,
        imageManager: ImageManager,
        runStore: PendingRunStore
    ) async -> HTTPResponse {
        let path = request.strippedPath
        let method = request.method

        // Health check — Docker CLI hits this first, without a version prefix
        if method == "GET" && (path == "/_ping" || path == "/ping") {
            return .text(200, body: "OK")
        }
        if method == "HEAD" && (path == "/_ping" || path == "/ping") {
            return .text(200, body: "")
        }

        // Version
        if method == "GET" && path == "/version" {
            return versionResponse()
        }

        // Info
        if method == "GET" && path == "/info" {
            return await infoResponse(engine: engine, imageManager: imageManager)
        }

        // Containers
        if method == "GET" && path == "/containers/json" {
            let all = request.queryItems["all"].map { $0 == "1" || $0 == "true" } ?? false
            return await listContainers(engine: engine, all: all)
        }

        if method == "POST" && path == "/containers/create" {
            return await pendingCreate(
                runStore: runStore,
                name: request.queryItems["name"],
                body: request.body
            )
        }

        if method == "GET" && path.hasPrefix("/containers/") && path.hasSuffix("/json") {
            let id = midSegment(path, prefix: "/containers/", suffix: "/json")
            return await inspectContainer(engine: engine, id: id)
        }

        if method == "POST" && path.hasPrefix("/containers/") && path.hasSuffix("/attach") {
            let id = midSegment(path, prefix: "/containers/", suffix: "/attach")
            return await attachContainer(engine: engine, runStore: runStore, id: id)
        }

        if method == "POST" && path.hasPrefix("/containers/") && path.hasSuffix("/start") {
            let id = midSegment(path, prefix: "/containers/", suffix: "/start")
            // Pending containers are started by the attach handler
            if await runStore.getConfig(id: id) != nil { return .noContent() }
            return await startContainer(engine: engine, id: id)
        }

        if method == "POST" && path.hasPrefix("/containers/") && path.hasSuffix("/stop") {
            let id = midSegment(path, prefix: "/containers/", suffix: "/stop")
            return await stopContainer(engine: engine, id: id)
        }

        if method == "POST" && path.hasPrefix("/containers/") && path.hasSuffix("/wait") {
            let id = midSegment(path, prefix: "/containers/", suffix: "/wait")
            return await waitContainer(runStore: runStore, id: id)
        }

        if method == "DELETE" && path.hasPrefix("/containers/") {
            let id = String(path.dropFirst("/containers/".count))
            // Remove pending containers; delegate real containers to the engine
            if await runStore.getConfig(id: id) != nil {
                await runStore.remove(id: id)
                return .noContent()
            }
            let force = request.queryItems["force"].map { $0 == "1" || $0 == "true" } ?? false
            return await removeContainer(engine: engine, id: id, force: force)
        }

        // Images
        if method == "GET" && path == "/images/json" {
            return await listImages(imageManager: imageManager)
        }

        if method == "POST" && path == "/images/create" {
            let fromImage = request.queryItems["fromImage"] ?? ""
            let tag = request.queryItems["tag"] ?? ""
            let ref = tag.isEmpty || tag == "latest" ? fromImage : "\(fromImage):\(tag)"
            return await pullImage(imageManager: imageManager, reference: ref)
        }

        if method == "GET" && path.hasPrefix("/images/") && path.hasSuffix("/json") {
            let name = midSegment(path, prefix: "/images/", suffix: "/json")
                .removingPercentEncoding ?? ""
            return await inspectImage(imageManager: imageManager, name: name)
        }

        // Podman libpod API – subset so `podman version`, `podman ps`, and `podman run` work
        // when CONTAINER_HOST points at the mocker socket.
        if path.hasPrefix("/libpod/") {
            let subpath = String(path.dropFirst("/libpod".count)) // "/libpod/foo" → "/foo"

            if method == "GET" && (subpath == "/_ping" || subpath == "/ping") {
                return .text(200, body: "OK")
            }
            if method == "HEAD" && (subpath == "/_ping" || subpath == "/ping") {
                return .text(200, body: "")
            }
            if method == "GET" && subpath == "/version" {
                return libpodVersionResponse()
            }
            if method == "GET" && subpath == "/info" {
                return await infoResponse(engine: engine, imageManager: imageManager)
            }
            if method == "GET" && subpath == "/containers/json" {
                let all = request.queryItems["all"].map { $0 == "1" || $0 == "true" } ?? false
                return await listContainers(engine: engine, all: all)
            }
            if method == "POST" && subpath == "/containers/create" {
                return await pendingCreate(
                    runStore: runStore,
                    name: request.queryItems["name"],
                    body: request.body,
                    libpod: true
                )
            }
            if method == "POST" && subpath.hasPrefix("/containers/") && subpath.hasSuffix("/attach") {
                let id = midSegment(subpath, prefix: "/containers/", suffix: "/attach")
                return await attachContainer(engine: engine, runStore: runStore, id: id)
            }
            if method == "POST" && subpath.hasPrefix("/containers/") && subpath.hasSuffix("/start") {
                let id = midSegment(subpath, prefix: "/containers/", suffix: "/start")
                if await runStore.getConfig(id: id) != nil { return .noContent() }
                return await startContainer(engine: engine, id: id)
            }
            if method == "POST" && subpath.hasPrefix("/containers/") && subpath.hasSuffix("/wait") {
                let id = midSegment(subpath, prefix: "/containers/", suffix: "/wait")
                return await waitContainer(runStore: runStore, id: id, libpod: true)
            }
            if method == "GET" && subpath.hasPrefix("/containers/") && subpath.hasSuffix("/json") {
                let id = midSegment(subpath, prefix: "/containers/", suffix: "/json")
                return await libpodInspectContainer(engine: engine, runStore: runStore, id: id)
            }
            if method == "DELETE" && subpath.hasPrefix("/containers/") {
                let id = String(subpath.dropFirst("/containers/".count))
                struct RmReport: Encodable, Sendable { let Id: String }
                if await runStore.getConfig(id: id) != nil {
                    await runStore.remove(id: id)
                    return .json(body: [RmReport(Id: id)])
                }
                let force = request.queryItems["force"].map { $0 == "1" || $0 == "true" } ?? false
                do {
                    _ = try await engine.remove(id, force: force)
                    return .json(body: [RmReport(Id: id)])
                } catch let error as MockerError {
                    if case .containerNotFound = error { return .error(404, message: error.localizedDescription) }
                    return .error(500, message: error.localizedDescription)
                } catch {
                    return .error(500, message: "\(error)")
                }
            }
            if method == "GET" && subpath == "/images/json" {
                return await listImages(imageManager: imageManager)
            }
            if method == "POST" && subpath == "/images/pull" {
                let ref = request.queryItems["reference"] ?? ""
                return await pullImage(imageManager: imageManager, reference: ref)
            }
            if method == "GET" && subpath.hasPrefix("/images/") && subpath.hasSuffix("/json") {
                let name = midSegment(subpath, prefix: "/images/", suffix: "/json")
                    .removingPercentEncoding ?? ""
                return await inspectImage(imageManager: imageManager, name: name)
            }
            return .error(404, message: "libpod endpoint not implemented: \(path)")
        }

        return .error(404, message: "page not found")
    }

    private static func midSegment(_ path: String, prefix: String, suffix: String) -> String {
        var s = path
        if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)) }
        if s.hasSuffix(suffix) { s = String(s.dropLast(suffix.count)) }
        return s
    }
}

// MARK: - Handler Implementations

extension DockerAPIHandlers {
    static func versionResponse() -> HTTPResponse {
        let ver = MockerConfig.mockerVersion
        let arch: String = {
            #if arch(arm64)
            return "arm64"
            #else
            return "amd64"
            #endif
        }()
        let response = DockerVersionResponse(
            Platform: .init(Name: "Mocker Engine"),
            Version: ver,
            ApiVersion: DockerAPIServer.apiVersion,
            MinAPIVersion: "1.24",
            GitCommit: "mocker",
            GoVersion: "swift",
            Os: "linux",
            Arch: arch,
            KernelVersion: "Apple Containerization",
            BuildTime: "2026-01-01T00:00:00.000000000+00:00"
        )
        return .json(body: response)
    }

    static func infoResponse(engine: ContainerEngine, imageManager: ImageManager) async -> HTTPResponse {
        let containers = (try? await engine.list(all: true)) ?? []
        let images = (try? await imageManager.list()) ?? []
        let running = containers.filter { $0.state == .running }.count
        let paused = containers.filter { $0.state == .paused }.count
        let stopped = containers.count - running - paused
        let info = ProcessInfo.processInfo
        let arch: String = {
            #if arch(arm64)
            return "arm64"
            #else
            return "amd64"
            #endif
        }()
        let response = DockerInfoResponse(
            ID: "mocker-\(arch)",
            Containers: containers.count,
            ContainersRunning: running,
            ContainersPaused: paused,
            ContainersStopped: stopped,
            Images: images.count,
            Driver: "apple-containerization",
            ServerVersion: MockerConfig.mockerVersion,
            OperatingSystem: "macOS \(info.operatingSystemVersionString)",
            OSType: "linux",
            Architecture: arch,
            NCPU: info.processorCount,
            MemTotal: Int64(info.physicalMemory),
            DockerRootDir: MockerConfig().dataRoot,
            HttpProxy: "",
            HttpsProxy: "",
            NoProxy: "",
            Name: Host.current().name ?? "localhost",
            Labels: [],
            ExperimentalBuild: false,
            LiveRestoreEnabled: false
        )
        return .json(body: response)
    }

    static func listContainers(engine: ContainerEngine, all: Bool) async -> HTTPResponse {
        let containers = (try? await engine.list(all: all)) ?? []
        let items = containers.map { c -> DockerContainerListItem in
            let ports = c.ports.map { p -> DockerPort in
                DockerPort(
                    IP: "0.0.0.0",
                    PrivatePort: Int(p.containerPort),
                    PublicPort: Int(p.hostPort),
                    proto: p.portProtocol.rawValue
                )
            }
            return DockerContainerListItem(
                Id: c.id,
                Names: ["/\(c.name)"],
                Image: c.image,
                ImageID: "sha256:\(c.id)",
                Command: c.command.isEmpty ? "" : c.command,
                Created: Int64(c.created.timeIntervalSince1970),
                State: c.state.rawValue,
                Status: c.status,
                Ports: ports,
                Labels: c.labels,
                NetworkSettings: DockerNetworkSettings(
                    Networks: [
                        "bridge": DockerNetwork(
                            IPAddress: c.networkAddress,
                            Gateway: "",
                            MacAddress: ""
                        )
                    ]
                ),
                Mounts: [],
                HostConfig: DockerHostConfig(NetworkMode: "default")
            )
        }
        return .json(body: items)
    }

    static func inspectContainer(engine: ContainerEngine, id: String) async -> HTTPResponse {
        guard let c = try? await engine.inspect(id) else {
            return .error(404, message: "No such container: \(id)")
        }
        let running = c.state == .running
        let now = ISO8601DateFormatter().string(from: c.created)
        let inspect = DockerContainerInspect(
            Id: c.id,
            Created: now,
            Path: c.command.split(separator: " ").first.map(String.init) ?? "",
            Args: c.command.split(separator: " ").dropFirst().map(String.init),
            State: DockerContainerState(
                Status: c.state.rawValue,
                Running: running,
                Paused: c.state == .paused,
                Restarting: false,
                Dead: c.state == .dead,
                Pid: c.pid ?? 0,
                ExitCode: 0,
                Error: "",
                StartedAt: running ? now : "0001-01-01T00:00:00Z",
                FinishedAt: running ? "0001-01-01T00:00:00Z" : now
            ),
            Image: c.image,
            Name: "/\(c.name)",
            Config: DockerContainerConfig(
                Hostname: c.name,
                Image: c.image,
                Labels: c.labels,
                Cmd: c.command.isEmpty ? [] : c.command.split(separator: " ").map(String.init),
                Env: [],
                WorkingDir: "",
                Entrypoint: nil
            ),
            HostConfig: DockerInspectHostConfig(
                Binds: [],
                NetworkMode: "default",
                PortBindings: [:],
                RestartPolicy: DockerRestartPolicy(Name: "no", MaximumRetryCount: 0),
                Memory: 0,
                CpuShares: 0
            ),
            NetworkSettings: DockerInspectNetworkSettings(
                IPAddress: c.networkAddress,
                Networks: [
                    "bridge": DockerNetwork(
                        IPAddress: c.networkAddress,
                        Gateway: "",
                        MacAddress: ""
                    )
                ]
            ),
            Mounts: []
        )
        return .json(body: inspect)
    }

    static func libpodInspectContainer(engine: ContainerEngine, runStore: PendingRunStore, id: String) async -> HTTPResponse {
        struct LibpodState: Encodable, Sendable {
            let Status: String
            let Running: Bool
            let ExitCode: Int32
            let Dead: Bool
            let Pid: Int
            let OOMKilled: Bool
            let Error: String
            let StartedAt: String
            let FinishedAt: String
        }
        struct LibpodConfig: Encodable, Sendable { let Image: String }
        struct LibpodInspect: Encodable, Sendable {
            let Id: String
            let Name: String
            let State: LibpodState
            let Image: String
            let ImageName: String
            let Config: LibpodConfig
        }
        let iso = ISO8601DateFormatter()
        let epoch = "0001-01-01T00:00:00Z"
        let now = iso.string(from: Date())
        if let entry = await runStore.getEntry(id: id) {
            let status = entry.exited ? "exited" : "running"
            return .json(body: LibpodInspect(
                Id: id,
                Name: entry.config.name ?? id,
                State: LibpodState(
                    Status: status,
                    Running: !entry.exited,
                    ExitCode: entry.exitCode,
                    Dead: false,
                    Pid: 0,
                    OOMKilled: false,
                    Error: "",
                    StartedAt: now,
                    FinishedAt: entry.exited ? now : epoch
                ),
                Image: entry.config.image,
                ImageName: entry.config.image,
                Config: LibpodConfig(Image: entry.config.image)
            ))
        }
        // Fall back to engine container
        guard let c = try? await engine.inspect(id) else {
            return .error(404, message: "No such container: \(id)")
        }
        let running = c.state == .running
        return .json(body: LibpodInspect(
            Id: c.id,
            Name: c.name,
            State: LibpodState(
                Status: c.state.rawValue,
                Running: running,
                ExitCode: 0,
                Dead: c.state == .dead,
                Pid: c.pid ?? 0,
                OOMKilled: false,
                Error: "",
                StartedAt: running ? now : epoch,
                FinishedAt: running ? epoch : now
            ),
            Image: c.image,
            ImageName: c.image,
            Config: LibpodConfig(Image: c.image)
        ))
    }

    static func startContainer(engine: ContainerEngine, id: String) async -> HTTPResponse {
        do {
            _ = try await engine.start(id)
            return .noContent()
        } catch let error as MockerError {
            if case .containerNotFound = error {
                return .error(404, message: error.localizedDescription)
            }
            return .error(500, message: error.localizedDescription)
        } catch {
            return .error(500, message: "\(error)")
        }
    }

    static func stopContainer(engine: ContainerEngine, id: String) async -> HTTPResponse {
        do {
            _ = try await engine.stop(id)
            return .noContent()
        } catch let error as MockerError {
            if case .containerNotFound = error {
                return .error(404, message: error.localizedDescription)
            }
            return .error(500, message: error.localizedDescription)
        } catch {
            return .error(500, message: "\(error)")
        }
    }

    static func removeContainer(engine: ContainerEngine, id: String, force: Bool) async -> HTTPResponse {
        do {
            _ = try await engine.remove(id, force: force)
            return .noContent()
        } catch let error as MockerError {
            if case .containerNotFound = error {
                return .error(404, message: error.localizedDescription)
            }
            return .error(500, message: error.localizedDescription)
        } catch {
            return .error(500, message: "\(error)")
        }
    }


    static func listImages(imageManager: ImageManager) async -> HTTPResponse {
        let images = (try? await imageManager.list()) ?? []
        let items = images.map { img -> DockerImageListItem in
            let tag = img.tag.isEmpty ? "latest" : img.tag
            let sizeSigned = Int64(clamping: img.size)
            return DockerImageListItem(
                Id: img.id,
                RepoTags: ["\(img.repository):\(tag)"],
                RepoDigests: [],
                Created: Int64(img.created.timeIntervalSince1970),
                Size: sizeSigned,
                VirtualSize: sizeSigned,
                Labels: [:]
            )
        }
        return .json(body: items)
    }

    static func inspectImage(imageManager: ImageManager, name: String) async -> HTTPResponse {
        guard let img = try? await imageManager.inspect(name) else {
            return .error(404, message: "No such image: \(name)")
        }
        let tag = img.tag.isEmpty ? "latest" : img.tag
        let arch: String = {
            #if arch(arm64)
            return "arm64"
            #else
            return "amd64"
            #endif
        }()
        let sizeSigned = Int64(clamping: img.size)
        let inspect = DockerImageInspect(
            Id: img.id,
            RepoTags: ["\(img.repository):\(tag)"],
            RepoDigests: [],
            Created: ISO8601DateFormatter().string(from: img.created),
            Size: sizeSigned,
            VirtualSize: sizeSigned,
            Labels: [:],
            Architecture: arch,
            Os: "linux",
            Config: DockerImageConfig(
                Cmd: [],
                Entrypoint: nil,
                Env: [],
                WorkingDir: "",
                Labels: [:]
            )
        )
        return .json(body: inspect)
    }

    static func pullImage(imageManager: ImageManager, reference: String) async -> HTTPResponse {
        guard !reference.isEmpty else {
            return .error(400, message: "missing fromImage parameter")
        }
        do {
            _ = try await imageManager.pull(reference)
            // Docker returns a stream of JSON progress objects; for simplicity return a single event
            struct PullProgress: Encodable, Sendable {
                let status: String
                let progressDetail: [String: String]
                let id: String
            }
            let progress = PullProgress(
                status: "Pull complete",
                progressDetail: [:],
                id: reference
            )
            return .json(body: progress)
        } catch {
            return .error(500, message: "\(error)")
        }
    }

    // MARK: - Pending-run create / attach / wait

    /// `POST /containers/create` (Docker) and `POST /libpod/containers/create` (Podman).
    ///
    /// Stores the container config in `PendingRunStore` and returns a synthetic container ID.
    /// The container is not actually started until `POST /containers/{id}/attach` is received.
    static func pendingCreate(
        runStore: PendingRunStore,
        name: String?,
        body: Data,
        libpod: Bool = false
    ) async -> HTTPResponse {
        let image: String
        let cmd: [String]
        let rm: Bool

        if libpod {
            struct LibpodCreate: Decodable, Sendable {
                let image: String
                let command: [String]?
                let remove: Bool?
                let name: String?
            }
            guard let decoded = try? JSONDecoder().decode(LibpodCreate.self, from: body) else {
                return .error(400, message: "invalid JSON body")
            }
            image = decoded.image
            cmd = decoded.command ?? []
            rm = decoded.remove ?? false
        } else {
            guard let decoded = try? JSONDecoder().decode(DockerContainerCreateBody.self, from: body) else {
                return .error(400, message: "invalid JSON body")
            }
            image = decoded.Image
            cmd = decoded.Cmd ?? []
            rm = false
        }

        var config = ContainerConfig(name: name, image: image, command: cmd)
        config.rm = rm

        let id = await runStore.create(config: config)
        struct CreateResponse: Encodable, Sendable { let Id: String; let Warnings: [String] }
        return .json(201, body: CreateResponse(Id: id, Warnings: []))
    }

    /// `POST /containers/{id}/attach` — HTTP 101 hijack, runs the container, streams output.
    static func attachContainer(
        engine: ContainerEngine,
        runStore: PendingRunStore,
        id: String
    ) async -> HTTPResponse {
        guard let config = await runStore.getConfig(id: id) else {
            return .error(404, message: "No such container: \(id)")
        }
        return HTTPResponse.hijack { fd in
            do {
                let exitCode = try await engine.runStreaming(config) { type, data in
                    DockerAPIServer.writeDockerFrame(fd: fd, type: type, data: data)
                }
                await runStore.recordExit(id: id, code: exitCode)
            } catch {
                let msg = Data("\(error)\n".utf8)
                DockerAPIServer.writeDockerFrame(fd: fd, type: 2, data: msg)
                await runStore.recordExit(id: id, code: 1)
            }
        }
    }

    /// `POST /containers/{id}/wait` — blocks until the container exits, returns its exit code.
    static func waitContainer(
        runStore: PendingRunStore,
        id: String,
        libpod: Bool = false
    ) async -> HTTPResponse {
        guard let exitCode = await runStore.waitForExit(id: id) else {
            return .error(404, message: "No such container: \(id)")
        }
        if libpod {
            struct LibpodWait: Encodable, Sendable {
                struct WaitError: Encodable, Sendable { let Message: String }
                let Error: WaitError
                let StatusCode: Int32
            }
            return .json(body: LibpodWait(Error: .init(Message: ""), StatusCode: exitCode))
        }
        struct WaitResponse: Encodable, Sendable { let StatusCode: Int32 }
        return .json(body: WaitResponse(StatusCode: exitCode))
    }
}

// MARK: - libpod version response

extension DockerAPIHandlers {
    static func libpodVersionResponse() -> HTTPResponse {
        struct LibpodVersionInfo: Encodable, Sendable {
            let APIVersion: String
            let Arch: String
            let BuildTime: String
            let GitCommit: String
            let GoVersion: String
            let MinAPIVersion: String
            let Os: String
            let Version: String
        }
        let arch: String = {
            #if arch(arm64)
            return "arm64"
            #else
            return "amd64"
            #endif
        }()
        return .json(body: LibpodVersionInfo(
            APIVersion: "5.0.0",
            Arch: arch,
            BuildTime: "",
            GitCommit: "",
            GoVersion: "",
            MinAPIVersion: "4.0.0",
            Os: "linux",
            Version: MockerConfig.mockerVersion
        ))
    }
}
