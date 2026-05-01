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
        imageManager: ImageManager
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
            let name = request.queryItems["name"]
            return await createContainer(engine: engine, name: name, body: request.body)
        }

        if method == "GET" && path.hasPrefix("/containers/") && path.hasSuffix("/json") {
            let id = midSegment(path, prefix: "/containers/", suffix: "/json")
            return await inspectContainer(engine: engine, id: id)
        }

        if method == "POST" && path.hasPrefix("/containers/") && path.hasSuffix("/start") {
            let id = midSegment(path, prefix: "/containers/", suffix: "/start")
            return await startContainer(engine: engine, id: id)
        }

        if method == "POST" && path.hasPrefix("/containers/") && path.hasSuffix("/stop") {
            let id = midSegment(path, prefix: "/containers/", suffix: "/stop")
            return await stopContainer(engine: engine, id: id)
        }

        if method == "DELETE" && path.hasPrefix("/containers/") {
            let id = String(path.dropFirst("/containers/".count))
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

    static func createContainer(engine: ContainerEngine, name: String?, body: Data) async -> HTTPResponse {
        guard let decoded = try? JSONDecoder().decode(DockerContainerCreateBody.self, from: body) else {
            return .error(400, message: "invalid JSON body")
        }

        var env: [String: String] = [:]
        for e in decoded.Env ?? [] {
            let parts = e.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { env[String(parts[0])] = String(parts[1]) }
        }

        var ports: [PortMapping] = []
        for (containerPort, bindings) in decoded.HostConfig?.PortBindings ?? [:] {
            for binding in bindings {
                let proto: PortProtocol = containerPort.hasSuffix("/udp") ? .udp : .tcp
                let cPort = UInt16(containerPort.split(separator: "/").first ?? "") ?? 0
                let hPort = UInt16(binding.HostPort) ?? 0
                ports.append(PortMapping(hostPort: hPort, containerPort: cPort, portProtocol: proto))
            }
        }

        var volumes: [VolumeMount] = []
        for bind in decoded.HostConfig?.Binds ?? [] {
            let parts = bind.split(separator: ":").map(String.init)
            if parts.count >= 2 {
                let ro = parts.count >= 3 && parts[2] == "ro"
                volumes.append(VolumeMount(source: parts[0], destination: parts[1], readOnly: ro))
            }
        }

        var config = ContainerConfig(
            name: name,
            image: decoded.Image,
            command: decoded.Cmd ?? [],
            environment: env,
            ports: ports,
            volumes: volumes,
            labels: decoded.Labels ?? [:]
        )
        if let wd = decoded.WorkingDir { config.workingDir = wd }
        if let user = decoded.User { config.user = user }
        if let ep = decoded.Entrypoint { config.entrypoint = ep.first }

        do {
            let c = try await engine.run(config)
            struct CreateResponse: Encodable, Sendable {
                let Id: String
                let Warnings: [String]
            }
            return .json(201, body: CreateResponse(Id: c.id, Warnings: []))
        } catch let err as MockerError {
            if case .containerAlreadyExists = err {
                return .error(409, message: err.localizedDescription)
            }
            return .error(500, message: err.localizedDescription)
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
}
