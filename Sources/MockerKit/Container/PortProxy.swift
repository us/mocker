import Foundation

/// Manages persistent port-forwarding subprocesses for a container.
/// Spawns a detached `mocker __proxy` process per port mapping that outlives the CLI invocation.
/// PIDs are stored in `~/.mocker/proxies/<containerID>/` so they can be killed on stop/rm.
public actor PortProxy {
    private let proxiesDir: String

    public init(proxiesDir: String) {
        self.proxiesDir = proxiesDir
    }

    /// Spawn background proxy processes for each port mapping.
    public func start(containerID: String, ports: [PortMapping], containerIP: String) throws {
        let dir = "\(proxiesDir)/\(containerID)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Find the mocker binary path (same binary we're running from)
        guard let mockerPath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first.map({ URL(fileURLWithPath: $0).path }),
              FileManager.default.fileExists(atPath: mockerPath) else {
            return
        }

        let rawIP = containerIP.split(separator: "/").first.map(String.init) ?? containerIP

        for port in ports {
            guard port.hostPort > 0, port.containerPort > 0 else { continue }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: mockerPath)
            process.arguments = [
                "__proxy",
                "--host-port", "\(port.hostPort)",
                "--container-ip", rawIP,
                "--container-port", "\(port.containerPort)"
            ]
            // Detach from parent — proxy outlives CLI
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            try process.run()

            // Save PID so we can kill it later
            let pidFile = "\(dir)/\(port.hostPort).pid"
            try "\(process.processIdentifier)".write(toFile: pidFile, atomically: true, encoding: .utf8)
        }
    }

    /// Kill all proxy processes for a container.
    public func stop(containerID: String) {
        let dir = "\(proxiesDir)/\(containerID)"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }

        for file in files where file.hasSuffix(".pid") {
            let pidFile = "\(dir)/\(file)"
            if let pidStr = try? String(contentsOfFile: pidFile, encoding: .utf8),
               let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                kill(pid, SIGTERM)
            }
            try? FileManager.default.removeItem(atPath: pidFile)
        }
        try? FileManager.default.removeItem(atPath: dir)
    }
}
