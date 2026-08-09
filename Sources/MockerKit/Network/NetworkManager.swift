import Foundation

/// Manages container networks through Apple's `container` CLI.
///
/// Networks used to live in a JSON file of mocker's own, disconnected from the runtime:
/// nothing it recorded existed as far as the backend was concerned, so a compose
/// project's `networks:` block had no effect on any container. Every operation now goes
/// to the real network store, which is what containers are actually attached to.
public actor NetworkManager {
    private let runner: ProcessRunning
    private let cli: String

    public init(
        config: MockerConfig = MockerConfig(),
        runner: ProcessRunning = RealProcessRunner(),
        cli: String = CLIResolver.resolve()
    ) throws {
        _ = config
        self.runner = runner
        self.cli = cli
    }

    /// Create a new network.
    /// - Parameters:
    ///   - driver: accepted for Docker surface parity; the backend has a single mode.
    ///   - gateway: likewise accepted and not forwarded — the backend derives it from the subnet.
    /// - Throws: the backend's own message, so a rejected name or an unavailable runtime
    ///   is distinguishable from "it already exists".
    public func create(
        name: String,
        driver: String = "bridge",
        subnet: String? = nil,
        gateway: String? = nil
    ) async throws -> NetworkInfo {
        // The runtime has a single mode and derives the gateway from the subnet. Saying
        // so beats reporting success for a network that does not match what was asked.
        if driver != "bridge" {
            FileHandle.standardError.write(Data(
                "WARNING: network driver \(driver) is not configurable; creating \(name) with the runtime's default\n".utf8))
        }
        if let gateway, !gateway.isEmpty {
            FileHandle.standardError.write(Data(
                "WARNING: --gateway is not configurable; the runtime derives it from the subnet\n".utf8))
        }

        var arguments = ["network", "create"]
        if let subnet, !subnet.isEmpty { arguments += ["--subnet", subnet] }
        arguments.append(name)

        let (output, status) = try await runner.run(executable: cli, arguments: arguments)
        guard status == 0 else {
            throw MockerError.operationFailed(Self.errorMessage(from: output, fallback: "failed to create network \(name)"))
        }
        // Read the created network back so callers see the subnet the backend assigned.
        return try await inspect(name)
    }

    /// List all networks.
    public func list() async throws -> [NetworkInfo] {
        let (output, status) = try await runner.run(executable: cli, arguments: ["network", "ls", "--format", "json"])
        guard status == 0 else {
            throw MockerError.operationFailed(Self.errorMessage(from: output, fallback: "failed to list networks"))
        }
        return Self.parseNetworks(output)
    }

    /// Remove a network.
    public func remove(_ name: String) async throws -> NetworkInfo {
        // Captured first so the caller can report what went, and so a missing network is
        // reported as such rather than as a generic CLI failure.
        let network = try await inspect(name)

        let (output, status) = try await runner.run(executable: cli, arguments: ["network", "delete", name])
        guard status == 0 else {
            throw MockerError.operationFailed(Self.errorMessage(from: output, fallback: "failed to remove network \(name)"))
        }
        return network
    }

    /// Inspect a network.
    public func inspect(_ name: String) async throws -> NetworkInfo {
        guard let match = try await list().first(where: { $0.name == name }) else {
            throw MockerError.networkNotFound(name)
        }
        return match
    }

    /// Connect a container to a network.
    public func connect(container: String, network: String) async throws {
        throw MockerError.operationFailed(
            "network connect is not yet supported with Apple Containerization")
    }

    /// Disconnect a container from a network.
    public func disconnect(container: String, network: String) async throws {
        throw MockerError.operationFailed(
            "network disconnect is not yet supported with Apple Containerization")
    }

    // MARK: - Parsing

    /// Decode `container network ls --format json`. Unparseable entries are skipped
    /// rather than failing the whole listing.
    static func parseNetworks(_ json: String) -> [NetworkInfo] {
        guard let data = json.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { entry in
            // The backend renamed this object between releases; accept both spellings so
            // an upgrade does not quietly blank out creation dates and labels.
            let config = (entry["config"] as? [String: Any])
                ?? (entry["configuration"] as? [String: Any])
                ?? [:]
            guard let name = (config["id"] as? String) ?? (entry["id"] as? String) else { return nil }
            let status = entry["status"] as? [String: Any] ?? [:]

            return NetworkInfo(
                id: name,
                name: name,
                driver: config["mode"] as? String ?? "nat",
                subnet: status["ipv4Subnet"] as? String,
                gateway: status["ipv4Gateway"] as? String,
                created: Self.parseCreationDate(config["creationDate"]),
                labels: config["labels"] as? [String: String] ?? [:]
            )
        }
        .sorted { $0.name < $1.name }
    }

    /// The backend has encoded this as both a reference-date interval and an ISO-8601
    /// string across releases; a wrong guess makes `network inspect` report "now" every time.
    static func parseCreationDate(_ value: Any?) -> Date? {
        if let seconds = value as? Double { return Date(timeIntervalSinceReferenceDate: seconds) }
        guard let text = value as? String else { return nil }
        return RelativeDate.parse(text)
    }

    /// Networks the runtime owns and that must never be pruned, identified the way the
    /// runtime itself marks them rather than by guessing at names.
    public static func isBuiltIn(_ network: NetworkInfo) -> Bool {
        network.labels["com.apple.container.resource.role"] == "builtin" || network.name == "default"
    }

    /// The backend prints its diagnostics on stderr, which the runner folds into the
    /// output; pass the last non-empty line through rather than a generic message.
    private static func errorMessage(from output: String, fallback: String) -> String {
        let lines = output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.last.map { $0.replacingOccurrences(of: "Error: ", with: "") } ?? fallback
    }
}
