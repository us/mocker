import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// MARK: - HTTP Types

/// A parsed HTTP/1.1 request received from the client.
struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let queryItems: [String: String]
    let headers: [String: String]
    let body: Data

    /// Path with the `/v{major}.{minor}` prefix stripped, e.g.
    /// `/v1.47/containers/json` → `/containers/json`.
    var strippedPath: String {
        guard path.hasPrefix("/v") else { return path }
        let tail = path.dropFirst(2) // drop "/v"
        // skip digits and one dot
        var idx = tail.startIndex
        while idx < tail.endIndex, tail[idx].isNumber || tail[idx] == "." {
            tail.formIndex(after: &idx)
        }
        guard idx < tail.endIndex, tail[idx] == "/" else { return path }
        return String(tail[idx...])
    }
}

/// An HTTP response to send back to the client.
struct HTTPResponse: Sendable {
    let status: Int
    let statusText: String
    let headers: [String: String]
    let body: Data
    /// When non-nil the server writes the response header, then calls this with the raw
    /// client fd (HTTP 101 / Docker container-attach hijack).
    let streamHandler: (@Sendable (Int32) async -> Void)?

    init(
        status: Int,
        statusText: String,
        headers: [String: String] = [:],
        body: Data = Data(),
        streamHandler: (@Sendable (Int32) async -> Void)? = nil
    ) {
        self.status = status
        self.statusText = statusText
        self.headers = headers
        self.body = body
        self.streamHandler = streamHandler
    }

    /// HTTP 101 response that hands off the raw fd to `handler`.
    /// Used for Docker container-attach: server writes the upgrade header then
    /// streams container output in Docker multiplexed-stream format.
    static func hijack(_ handler: @escaping @Sendable (Int32) async -> Void) -> HTTPResponse {
        HTTPResponse(
            status: 101,
            statusText: "UPGRADED",
            headers: [
                "Content-Type": "application/vnd.docker.raw-stream",
                "Connection": "Upgrade",
                "Upgrade": "tcp",
            ],
            streamHandler: handler
        )
    }

    static func json(_ status: Int = 200, body: some Encodable & Sendable) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(body)) ?? Data("{}".utf8)
        return HTTPResponse(
            status: status,
            statusText: statusPhrase(status),
            headers: [
                "Content-Type": "application/json",
                "Content-Length": "\(data.count)",
                "Api-Version": DockerAPIServer.apiVersion,
                "Server": "mocker/\(MockerConfig.mockerVersion)",
            ],
            body: data
        )
    }

    static func text(_ status: Int = 200, body: String) -> HTTPResponse {
        let data = Data(body.utf8)
        return HTTPResponse(
            status: status,
            statusText: statusPhrase(status),
            headers: [
                "Content-Type": "text/plain; charset=utf-8",
                "Content-Length": "\(data.count)",
                "Api-Version": DockerAPIServer.apiVersion,
                "Server": "mocker/\(MockerConfig.mockerVersion)",
            ],
            body: data
        )
    }

    static func error(_ status: Int, message: String) -> HTTPResponse {
        struct ErrorBody: Encodable, Sendable { let message: String }
        return json(status, body: ErrorBody(message: message))
    }

    static func noContent() -> HTTPResponse {
        HTTPResponse(
            status: 204,
            statusText: "No Content",
            headers: [
                "Api-Version": DockerAPIServer.apiVersion,
                "Server": "mocker/\(MockerConfig.mockerVersion)",
            ],
            body: Data()
        )
    }

    private static func statusPhrase(_ code: Int) -> String {
        switch code {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 304: "Not Modified"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 409: "Conflict"
        case 500: "Internal Server Error"
        default: "Unknown"
        }
    }
}

// MARK: - Pending Run Store

/// Coordinates the Docker/Podman create → attach → start → wait lifecycle.
///
/// `POST /containers/create` stores a `ContainerConfig` here.
/// `POST /containers/{id}/attach` runs the container and streams output.
/// `POST /containers/{id}/start`  is a no-op (attach already started it).
/// `POST /containers/{id}/wait`   blocks until attach records the exit code.
actor PendingRunStore {
    struct Entry {
        let config: ContainerConfig
        var exited = false
        var exitCode: Int32 = 0
        var waiters: [CheckedContinuation<Int32, Never>] = []
    }

    private var entries: [String: Entry] = [:]

    func create(config: ContainerConfig) -> String {
        let id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        entries[id] = Entry(config: config)
        return id
    }

    func getConfig(id: String) -> ContainerConfig? { entries[id]?.config }
    func getEntry(id: String) -> Entry? { entries[id] }

    func recordExit(id: String, code: Int32) {
        guard var e = entries[id] else { return }
        e.exited = true
        e.exitCode = code
        let waiters = e.waiters
        e.waiters = []
        entries[id] = e
        waiters.forEach { $0.resume(returning: code) }
    }

    func waitForExit(id: String) async -> Int32? {
        if let e = entries[id] {
            if e.exited { return e.exitCode }
            return await withCheckedContinuation { continuation in
                guard var entry = entries[id] else {
                    continuation.resume(returning: 0)
                    return
                }
                entry.waiters.append(continuation)
                entries[id] = entry
            }
        }
        return nil
    }

    func remove(id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        let code = entry.exitCode
        entry.waiters.forEach { $0.resume(returning: code) }
    }
}

// MARK: - Docker API Server

/// Serves the Docker Engine REST API over a Unix-domain socket.
///
/// The server can be started in two modes:
/// - **launchd socket activation**: call ``serve(serverFd:)`` with a socket fd
///   already bound and listening by launchd.
/// - **standalone**: call ``serve(socketPath:)`` to create and bind the socket.
///
/// In both modes the server exits automatically after `timeout` seconds of
/// inactivity (no active connections).  Pass `nil` to run indefinitely.
public actor DockerAPIServer {
    public nonisolated let containerEngine: ContainerEngine
    public nonisolated let imageManager: ImageManager
    let runStore = PendingRunStore()

    private var lastActivity: Date = Date()
    private var activeConnections: Int = 0
    private let timeout: TimeInterval?

    /// The Docker Engine API version advertised in responses.
    public static let apiVersion = "1.47"

    public init(config: MockerConfig, timeout: TimeInterval? = nil) throws {
        self.containerEngine = try ContainerEngine(config: config)
        self.imageManager = try ImageManager(config: config)
        self.timeout = timeout
    }

    // MARK: - Entry Points

    /// Serve on a socket fd already bound and listening (e.g. from launchd activation).
    public func serve(serverFd: Int32) async throws {
        startTimeoutMonitor()
        try await runAcceptLoop(serverFd: serverFd)
    }

    /// Create a Unix-domain socket at `socketPath` and serve.
    public func serve(socketPath: String) async throws {
        try? FileManager.default.removeItem(atPath: socketPath)
        let serverFd = try Self.bindAndListen(path: socketPath)
        defer { close(serverFd) }
        startTimeoutMonitor()
        try await runAcceptLoop(serverFd: serverFd)
    }

    // MARK: - Timeout

    private func startTimeoutMonitor() {
        guard let t = timeout else { return }
        let capturedTimeout = t
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if activeConnections == 0,
                   Date().timeIntervalSince(lastActivity) > capturedTimeout {
                    exit(0)
                }
            }
        }
    }

    // MARK: - Activity Tracking

    private func incrementConnections() {
        activeConnections += 1
        lastActivity = Date()
    }

    private func decrementConnections() {
        activeConnections -= 1
        lastActivity = Date()
    }

    // MARK: - Accept Loop

    private func runAcceptLoop(serverFd: Int32) async throws {
        let engine = containerEngine
        let imgMgr = imageManager
        let store = runStore
        while true {
            let clientFd = try await Self.acceptAsync(serverFd)
            incrementConnections()
            let server = self
            Task.detached {
                await Self.handleConnection(
                    clientFd: clientFd,
                    engine: engine,
                    imageManager: imgMgr,
                    runStore: store
                )
                close(clientFd)
                await server.decrementConnections()
            }
        }
    }

    // MARK: - Connection Handler

    private static func handleConnection(
        clientFd: Int32,
        engine: ContainerEngine,
        imageManager: ImageManager,
        runStore: PendingRunStore
    ) async {
        guard let request = await readHTTPRequest(fd: clientFd) else { return }
        let response = await DockerAPIHandlers.route(
            request: request,
            engine: engine,
            imageManager: imageManager,
            runStore: runStore
        )
        writeHTTPResponse(fd: clientFd, response: response)
        if let handler = response.streamHandler {
            await handler(clientFd)
        }
    }

    // MARK: - Socket Helpers

    /// Create a listening Unix-domain socket at `path`.
    public static func bindAndListen(path: String) throws -> Int32 {
        #if canImport(Darwin)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #else
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
        }

        var reuseVal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseVal, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let sunPathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < sunPathCapacity else {
            close(fd)
            throw MockerError.operationFailed("Socket path too long: \(path)")
        }
        path.withCString { cStr in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: sunPathCapacity) { dest in
                    _ = strncpy(dest, cStr, sunPathCapacity - 1)
                }
            }
        }

        let unlink_path = path  // captured for unlink before bind
        unlink_path.withCString { _ = unlink($0) }

        let bindResult = withUnsafePointer(to: addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sptr in
                bind(fd, sptr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
        }

        guard listen(fd, 128) == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
        }
        return fd
    }

    /// Bridge the blocking `accept(2)` call to Swift concurrency.
    private static func acceptAsync(_ serverFd: Int32) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let clientFd = accept(serverFd, nil, nil)
                if clientFd < 0 {
                    continuation.resume(
                        throwing: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
                    )
                } else {
                    continuation.resume(returning: clientFd)
                }
            }
        }
    }

    // MARK: - HTTP Parsing

    private static func readHTTPRequest(fd: Int32) async -> HTTPRequest? {
        var raw = Data()
        var headerEnd: Int? = nil
        let marker = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n

        while raw.count < 131_072 { // 128 KB guard: limits memory use from malformed/malicious headers
            let chunk = await readChunk(fd: fd, maxBytes: 4096)
            guard !chunk.isEmpty else { break }
            raw.append(chunk)
            if let r = raw.range(of: marker) {
                headerEnd = r.upperBound
                break
            }
        }

        guard let end = headerEnd else { return nil }

        let headerText = String(data: raw.prefix(end), encoding: .utf8) ?? ""
        let lines = headerText.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        // Request line: METHOD PATH HTTP/1.x
        let reqParts = lines[0].split(separator: " ", maxSplits: 2).map(String.init)
        guard reqParts.count >= 2 else { return nil }

        let method = reqParts[0]
        let rawPath = reqParts[1]

        // Split path / query string
        var path = rawPath
        var queryItems: [String: String] = [:]
        if let q = rawPath.firstIndex(of: "?") {
            path = String(rawPath[..<q])
            let qs = String(rawPath[rawPath.index(after: q)...])
            for pair in qs.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                let key = String(kv[0])
                let value = kv.count > 1
                    ? (String(kv[1]).removingPercentEncoding ?? String(kv[1]))
                    : ""
                queryItems[key] = value
            }
        }

        // Headers (lowercase keys)
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = val
        }

        // Body
        var body = Data()
        if let cl = headers["content-length"].flatMap(Int.init), cl > 0 {
            let already = raw.count - end
            if already > 0 { body.append(raw.suffix(already)) }
            let remaining = cl - body.count
            if remaining > 0 {
                let more = await readExact(fd: fd, count: remaining)
                body.append(more)
            }
        }

        return HTTPRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            headers: headers,
            body: body
        )
    }

    private static func readChunk(fd: Int32, maxBytes: Int) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var buf = [UInt8](repeating: 0, count: maxBytes)
                let n = recv(fd, &buf, maxBytes, 0)
                continuation.resume(returning: n > 0 ? Data(buf.prefix(n)) : Data())
            }
        }
    }

    private static func readExact(fd: Int32, count: Int) async -> Data {
        var data = Data()
        while data.count < count {
            let chunk = await readChunk(fd: fd, maxBytes: count - data.count)
            guard !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return data
    }

    // MARK: - HTTP Writing

    private static func writeHTTPResponse(fd: Int32, response: HTTPResponse) {
        var head = "HTTP/1.1 \(response.status) \(response.statusText)\r\n"
        for (k, v) in response.headers { head += "\(k): \(v)\r\n" }
        if response.status != 101 { head += "Connection: close\r\n" }
        head += "\r\n"

        var data = Data(head.utf8)
        data.append(response.body)

        data.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = send(fd, ptr.advanced(by: sent), data.count - sent, 0)
                guard n > 0 else { break }
                sent += n
            }
        }
    }
    // MARK: - Docker Multiplexed-Stream Frame

    /// Write one Docker multiplexed-stream frame directly to a raw fd.
    ///
    /// Frame layout: `[type(1)] [0,0,0] [payloadSize(4 BE)] [payload]`
    ///
    /// - Parameters:
    ///   - fd:   Raw client file descriptor from the accept loop.
    ///   - type: `1` = stdout, `2` = stderr.
    ///   - data: Payload bytes to include in this frame.
    static func writeDockerFrame(fd: Int32, type: UInt8, data: Data) {
        guard !data.isEmpty else { return }
        var frame = Data(repeating: 0, count: 8)
        frame[0] = type
        let size = UInt32(data.count)
        frame[4] = UInt8((size >> 24) & 0xFF)
        frame[5] = UInt8((size >> 16) & 0xFF)
        frame[6] = UInt8((size >> 8) & 0xFF)
        frame[7] = UInt8(size & 0xFF)
        var out = frame
        out.append(data)
        out.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress else { return }
            var sent = 0
            while sent < out.count {
                let n = send(fd, ptr.advanced(by: sent), out.count - sent, 0)
                guard n > 0 else { break }
                sent += n
            }
        }
    }
}


/// Attempt to acquire a socket fd previously bound by launchd.
///
/// Returns the first file descriptor for the socket named `name`, or `nil`
/// if this process was not started via launchd socket activation.
/// On non-Darwin platforms (e.g. Linux CI) this always returns `nil`.
public func launchdActivateSocket(name: String) -> Int32? {
    #if canImport(Darwin)
    var fds: UnsafeMutablePointer<Int32>? = nil
    var count: size_t = 0
    // launch_activate_socket expects UnsafeMutablePointer<UnsafeMutablePointer<Int32>> (non-optional
    // inner pointer), but &fds from an Optional gives the optional-inner variant. Rebind the
    // storage — Optional<UnsafeMutablePointer<Int32>> and UnsafeMutablePointer<Int32> have the
    // same memory layout (8 bytes; nil == null pointer), so this is safe.
    let result: Int32 = withUnsafeMutablePointer(to: &fds) { optPtr in
        optPtr.withMemoryRebound(to: UnsafeMutablePointer<Int32>.self, capacity: 1) { ptr in
            launch_activate_socket(name, ptr, &count)
        }
    }
    guard result == 0, let fds, count > 0 else { return nil }
    let fd = fds[0]
    free(fds)
    return fd
    #else
    return nil
    #endif
}
