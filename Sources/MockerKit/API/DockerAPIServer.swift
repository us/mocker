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
/// Phase 1 (read-only): `/_ping`, `/version`. Handlers grow per the plan.
public final class DockerAPIServer: @unchecked Sendable {
    private let socketPath: String
    private let mockerVersion: String
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?

    public init(socketPath: String, mockerVersion: String) {
        self.socketPath = socketPath
        self.mockerVersion = mockerVersion
    }

    public func run() async throws {
        try Self.prepareSocketPath(socketPath)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        let version = mockerVersion
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(mockerVersion: version))
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

/// Per-connection HTTP handler. Phase 1 routes are static (no engine), so fully synchronous.
/// `@unchecked Sendable`: a ChannelHandler is confined to its own event loop; its mutable state
/// (`reqHead`) is only touched there.
final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let mockerVersion: String
    private var reqHead: HTTPRequestHead?

    init(mockerVersion: String) { self.mockerVersion = mockerVersion }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head): reqHead = head
        case .body: break  // Phase 1 endpoints take no body
        case .end:
            guard let head = reqHead else { return }
            route(context: context, head: head)
            reqHead = nil
        }
    }

    private func route(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let path = Self.normalizePath(head.uri)
        switch (head.method, path) {
        case (.GET, "/_ping"), (.HEAD, "/_ping"):
            writePing(context, head: head)
        case (.GET, "/version"):
            writeJSON(context, head: head, status: .ok, object: versionJSON())
        default:
            writeJSON(context, head: head, status: .notFound, object: ["message": "page not found: \(path)"])
        }
    }

    // MARK: responses

    private func writePing(_ context: ChannelHandlerContext, head: HTTPRequestHead) {
        let isHead = head.method == .HEAD
        var headers = baseHeaders()
        headers.add(name: "OSType", value: "linux")
        headers.add(name: "Builder-Version", value: "1")
        headers.add(name: "Swarm", value: "inactive")
        headers.add(name: "Cache-Control", value: "no-cache, no-store, must-revalidate")
        headers.add(name: "Pragma", value: "no-cache")
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        let body = "OK"
        headers.add(name: "Content-Length", value: String(isHead ? 0 : body.utf8.count))
        context.write(wrapOutboundOut(.head(.init(version: head.version, status: .ok, headers: headers))), promise: nil)
        if !isHead {
            var buf = context.channel.allocator.buffer(capacity: body.utf8.count)
            buf.writeString(body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        }
        finish(context, head: head)
    }

    private func writeJSON(_ context: ChannelHandlerContext, head: HTTPRequestHead, status: HTTPResponseStatus, object: [String: Any]) {
        let isHead = head.method == .HEAD
        let data = Self.jsonData(object)
        var headers = baseHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: String(isHead ? 0 : data.count))
        context.write(wrapOutboundOut(.head(.init(version: head.version, status: status, headers: headers))), promise: nil)
        if !isHead {
            var buf = context.channel.allocator.buffer(capacity: data.count)
            buf.writeBytes(data)
            context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        }
        finish(context, head: head)
    }

    /// Serialize a JSON object with **unescaped slashes** — Docker emits `docker.io/library/...`,
    /// not `docker.io\/library\/...`. `JSONSerialization` always escapes `/`, so undo it (it only
    /// ever produces `\/` for a forward slash, so the replace is safe).
    static func jsonData(_ object: [String: Any]) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return Data("{}".utf8) }
        return Data(str.replacingOccurrences(of: "\\/", with: "/").utf8)
    }

    /// `Api-Version` (+ `Docker-Experimental`) on EVERY response — if absent the Go client falls
    /// back to its own max version and sends a too-new path.
    private func baseHeaders() -> HTTPHeaders {
        var h = HTTPHeaders()
        h.add(name: "Api-Version", value: DockerAPI.version)
        h.add(name: "Docker-Experimental", value: "false")
        return h
    }

    private func finish(_ context: ChannelHandlerContext, head: HTTPRequestHead) {
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        if !head.isKeepAlive { context.close(promise: nil) }
    }

    private func versionJSON() -> [String: Any] {
        [
            "Platform": ["Name": "mocker"],
            "Version": mockerVersion,
            "ApiVersion": DockerAPI.version,
            "MinAPIVersion": DockerAPI.minVersion,
            "Os": "linux",
            "Arch": "arm64",
            "KernelVersion": "",
            "GoVersion": "",
            "GitCommit": "",
            "BuildTime": "",
            "Experimental": false,
            // `docker version`'s Server/Engine block reads OS-Arch, min-version, etc. from the
            // component Details, not the top-level fields — populate them so it isn't blank.
            "Components": [
                [
                    "Name": "Engine",
                    "Version": mockerVersion,
                    "Details": [
                        "ApiVersion": DockerAPI.version,
                        "MinAPIVersion": DockerAPI.minVersion,
                        "Os": "linux",
                        "Arch": "arm64",
                        "Experimental": "false",
                    ],
                ]
            ],
        ]
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
}
