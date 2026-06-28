import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1

/// Advertised Docker Engine API version. Single source of truth for `/_ping` + `/version`.
/// 1.47 matches the CLI (`Version.swift`); clients always clamp DOWN to this. MinAPIVersion is
/// the pre-negotiation floor — we never *enforce* it (lenient path handling accepts any `/vX.YY`).
public enum DockerAPI {
    public static let version = "1.47"
    public static let minVersion = "1.24"
}

struct DockerAPIError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// A Docker Engine API server over a Unix domain socket, backed by MockerKit.
/// Phase 1 (read-only): ping/version/info + container & image LIST/INSPECT.
public final class DockerAPIServer: @unchecked Sendable {
    private let socketPath: String
    private let mockerVersion: String
    private let engine: ContainerEngine
    private let images: ImageManager
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?

    public init(socketPath: String, mockerVersion: String, engine: ContainerEngine, images: ImageManager) {
        self.socketPath = socketPath
        self.mockerVersion = mockerVersion
        self.engine = engine
        self.images = images
    }

    public func run() async throws {
        try Self.prepareSocketPath(socketPath)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        let version = mockerVersion, engine = self.engine, images = self.images
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(mockerVersion: version, engine: engine, images: images))
                }
            }
        // cleanupExistingSocketFile:false — NIO's cleanup uses stat() with no owner/symlink check;
        // prepareSocketPath() already did a safe lstat-preflight unlink.
        let channel = try await bootstrap.bind(unixDomainSocketPath: socketPath, cleanupExistingSocketFile: false).get()
        chmod(socketPath, 0o600)  // restrict to owner (parent dir is already 0700)
        self.channel = channel
        try await channel.closeFuture.get()
    }

    public func shutdown() async {
        try? await channel?.close().get()
        try? await group?.shutdownGracefully()
        unlink(socketPath)
    }

    /// Safe stale-socket cleanup: create the parent dir 0700, and unlink an existing path ONLY if
    /// it is a socket owned by the current user (lstat — never follows a symlink).
    static func prepareSocketPath(_ path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var st = stat()
        if lstat(path, &st) == 0 {
            let isSocket = (st.st_mode & S_IFMT) == S_IFSOCK
            guard isSocket, st.st_uid == getuid() else {
                throw DockerAPIError(message: "refusing to remove non-socket or non-owned file at \(path)")
            }
            unlink(path)
        }
    }
}

/// Per-connection HTTP handler. Engine-backed routes hop to an async `Task` and write back via the
/// **Channel** (thread-safe), never the `ChannelHandlerContext` (event-loop only — Swift 6 unsafe).
/// `@unchecked Sendable`: a ChannelHandler is confined to its own event loop; engine/images are
/// actors (Sendable), and `reqHead` is only touched on the loop.
final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let mockerVersion: String
    private let engine: ContainerEngine
    private let images: ImageManager
    private var reqHead: HTTPRequestHead?

    init(mockerVersion: String, engine: ContainerEngine, images: ImageManager) {
        self.mockerVersion = mockerVersion
        self.engine = engine
        self.images = images
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head): reqHead = head
        case .body: break  // read endpoints take no body
        case .end:
            guard let head = reqHead else { return }
            route(channel: context.channel, head: head)
            reqHead = nil
        }
    }

    private func route(channel: Channel, head: HTTPRequestHead) {
        let path = Self.normalizePath(head.uri)
        let query = Self.parseQuery(head.uri)
        switch (head.method, path) {
        case (.GET, "/_ping"), (.HEAD, "/_ping"):
            respondPing(channel, head)
        case (.GET, "/version"):
            respondJSON(channel, head, .ok, versionJSON())
        case (.GET, "/info"):
            Task { self.respondJSON(channel, head, .ok, await self.infoJSON()) }
        case (.GET, "/containers/json"):
            let all = ["1", "true", "True"].contains(query["all"] ?? "false")
            Task {
                do { self.respondJSON(channel, head, .ok, try await self.engine.list(all: all).map(mapToContainerListItem)) }
                catch { self.respondError(channel, head, .internalServerError, "\(error)") }
            }
        case (.GET, "/images/json"):
            Task {
                do { self.respondJSON(channel, head, .ok, try await self.images.list().map(mapToImageListItem)) }
                catch { self.respondError(channel, head, .internalServerError, "\(error)") }
            }
        case (.GET, let p) where p.hasPrefix("/containers/") && p.hasSuffix("/json") && p != "/containers/json":
            let id = String(p.dropFirst("/containers/".count).dropLast("/json".count))
            Task {
                if let info = try? await self.engine.inspect(id) {
                    self.respondEncodable(channel, head, .ok, mapToContainerInspect(info))
                } else {
                    self.respondError(channel, head, .notFound, "No such container: \(id)")
                }
            }
        default:
            respondError(channel, head, .notFound, "page not found: \(path)")
        }
    }

    // MARK: - /info & /version bodies

    private func infoJSON() async -> [String: Any] {
        let containers = (try? await engine.list(all: true)) ?? []
        let running = containers.filter { $0.state == .running }.count
        let imageCount = ((try? await images.list()) ?? []).count
        return [
            "ID": "MOCKER",
            "Containers": containers.count,
            "ContainersRunning": running,
            "ContainersPaused": 0,
            "ContainersStopped": containers.count - running,
            "Images": imageCount,
            "Driver": "apple-container",
            "DockerRootDir": "/var/lib/mocker",
            "OSType": "linux",
            "OperatingSystem": "Apple Containerization",
            "Architecture": "aarch64",
            "NCPU": ProcessInfo.processInfo.processorCount,
            "MemTotal": Int(ProcessInfo.processInfo.physicalMemory),
            "ServerVersion": mockerVersion,
            "DefaultRuntime": "runc",
            "Name": Host.current().localizedName ?? "mocker",
            "IndexServerAddress": "https://index.docker.io/v1/",
        ]
    }

    private func versionJSON() -> [String: Any] {
        [
            "Platform": ["Name": "mocker"],
            "Version": mockerVersion,
            "ApiVersion": DockerAPI.version,
            "MinAPIVersion": DockerAPI.minVersion,
            "Os": "linux",
            "Arch": "arm64",
            "Experimental": false,
            // `docker version`'s Server/Engine block reads OS-Arch, min-version, etc. from the
            // component Details, not the top-level fields — populate them so it isn't blank.
            "Components": [
                [
                    "Name": "Engine", "Version": mockerVersion,
                    "Details": [
                        "ApiVersion": DockerAPI.version, "MinAPIVersion": DockerAPI.minVersion,
                        "Os": "linux", "Arch": "arm64", "Experimental": "false",
                    ],
                ]
            ],
        ]
    }

    // MARK: - Responses (Channel-based, safe to call from an async Task)

    private func respondPing(_ channel: Channel, _ head: HTTPRequestHead) {
        var headers = baseHeaders()
        headers.add(name: "OSType", value: "linux")
        headers.add(name: "Builder-Version", value: "1")
        headers.add(name: "Swarm", value: "inactive")
        headers.add(name: "Cache-Control", value: "no-cache, no-store, must-revalidate")
        headers.add(name: "Pragma", value: "no-cache")
        write(channel, head, status: .ok, contentType: "text/plain; charset=utf-8", body: Data("OK".utf8), headers: headers)
    }

    private func respondJSON(_ channel: Channel, _ head: HTTPRequestHead, _ status: HTTPResponseStatus, _ value: Any) {
        write(channel, head, status: status, contentType: "application/json", body: Self.jsonData(value), headers: baseHeaders())
    }

    private func respondEncodable<T: Encodable>(_ channel: Channel, _ head: HTTPRequestHead, _ status: HTTPResponseStatus, _ value: T) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let body = (try? enc.encode(value)) ?? Data("{}".utf8)
        write(channel, head, status: status, contentType: "application/json", body: body, headers: baseHeaders())
    }

    /// Docker error shape: `{"message": "..."}`.
    private func respondError(_ channel: Channel, _ head: HTTPRequestHead, _ status: HTTPResponseStatus, _ message: String) {
        respondJSON(channel, head, status, ["message": message])
    }

    private func write(_ channel: Channel, _ head: HTTPRequestHead, status: HTTPResponseStatus, contentType: String, body: Data, headers baseHeaders: HTTPHeaders) {
        let isHead = head.method == .HEAD
        var headers = baseHeaders
        headers.add(name: "Content-Type", value: contentType)
        headers.add(name: "Content-Length", value: String(isHead ? 0 : body.count))
        let respHead = HTTPResponseHead(version: head.version, status: status, headers: headers)
        channel.write(HTTPServerResponsePart.head(respHead), promise: nil)
        if !isHead {
            var buf = channel.allocator.buffer(capacity: body.count)
            buf.writeBytes(body)
            channel.write(HTTPServerResponsePart.body(.byteBuffer(buf)), promise: nil)
        }
        let done = channel.writeAndFlush(HTTPServerResponsePart.end(nil))
        if !head.isKeepAlive { done.whenComplete { _ in channel.close(promise: nil) } }
    }

    /// `Api-Version` (+ `Docker-Experimental`) on EVERY response — if absent the Go client falls
    /// back to its own max version and sends a too-new path.
    private func baseHeaders() -> HTTPHeaders {
        var h = HTTPHeaders()
        h.add(name: "Api-Version", value: DockerAPI.version)
        h.add(name: "Docker-Experimental", value: "false")
        return h
    }

    /// Serialize a JSON value (object OR array) with **unescaped slashes** for Docker parity.
    /// `JSONSerialization` always escapes `/`, so undo it (it only ever produces `\/` for a slash).
    static func jsonData(_ value: Any) -> Data {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return Data("{}".utf8) }
        return Data(str.replacingOccurrences(of: "\\/", with: "/").utf8)
    }

    /// Strip a query string and a leading `/vX.YY` version prefix (clients pin versions into the
    /// path; we accept ANY and never enforce min/max).
    static func normalizePath(_ uri: String) -> String {
        var p = uri
        if let q = p.firstIndex(of: "?") { p = String(p[..<q]) }
        if p.hasPrefix("/v") {
            let after = p.dropFirst(2)
            if let slash = after.firstIndex(of: "/") {
                let ver = after[after.startIndex..<slash]
                if !ver.isEmpty, ver.allSatisfy({ $0.isNumber || $0 == "." }) {
                    p = String(after[slash...])
                }
            }
        }
        return p
    }

    /// Parse the query string into a dict (best-effort, last value wins; percent-decoded).
    static func parseQuery(_ uri: String) -> [String: String] {
        guard let q = uri.firstIndex(of: "?") else { return [:] }
        var out: [String: String] = [:]
        for pair in uri[uri.index(after: q)...].split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
            let val = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? String(kv[1])) : ""
            out[key] = val
        }
        return out
    }
}
