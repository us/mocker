import ArgumentParser
import Foundation
import MockerKit

struct SocketCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "socket",
        abstract: "Manage the Mocker Docker-compatible Unix socket",
        subcommands: [
            SocketInstall.self,
            SocketUninstall.self,
            SocketStatus.self,
        ]
    )
}

// MARK: - mocker socket install

struct SocketInstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install and activate the launchd socket agent"
    )

    @Option(name: .long, help: "Custom socket path (default: ~/.mocker/mocker.sock)")
    var socketPath: String?

    func run() async throws {
        let config = MockerConfig()
        let sock = socketPath ?? config.socketPath
        let plistPath = config.launchAgentPlistPath
        let binaryPath = resolveBinaryPath()

        // Ensure ~/.mocker directory exists
        try config.ensureDirectories()

        // Write plist
        let plistContent = buildPlist(binaryPath: binaryPath, socketPath: sock)
        let plistURL = URL(fileURLWithPath: plistPath)
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)

        // Bootstrap the launchd agent
        let uid = getuid()
        let (_, exitCode) = try await runProcess(
            "/bin/launchctl",
            ["bootstrap", "gui/\(uid)", plistPath]
        )

        if exitCode == 0 {
            print("Mocker socket agent installed.")
            print("Socket path: \(sock)")
            print("Set DOCKER_HOST=unix://\(sock) to use it with Docker-compatible tools.")
        } else {
            // Already loaded — try to unload and reload
            _ = try? await runProcess("/bin/launchctl", ["bootout", "gui/\(uid)", MockerConfig.launchAgentLabel])
            let (_, rc2) = try await runProcess(
                "/bin/launchctl",
                ["bootstrap", "gui/\(uid)", plistPath]
            )
            if rc2 == 0 {
                print("Mocker socket agent reinstalled.")
                print("Socket path: \(sock)")
            } else {
                print("Warning: launchctl bootstrap returned exit code \(rc2).")
                print("Plist written to: \(plistPath)")
                print("Run manually: launchctl bootstrap gui/\(uid) \(plistPath)")
            }
        }
    }

    private func buildPlist(binaryPath: String, socketPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>io.mocker.socket</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binaryPath)</string>
                <string>system</string>
                <string>service</string>
                <string>--timeout</string>
                <string>5s</string>
            </array>
            <key>Sockets</key>
            <dict>
                <key>MockerSocket</key>
                <dict>
                    <key>SockPathName</key>
                    <string>\(socketPath)</string>
                </dict>
            </dict>
            <key>RunAtLoad</key>
            <false/>
        </dict>
        </plist>
        """
    }

    private func resolveBinaryPath() -> String {
        // Use the path of the currently running mocker binary
        let arg0 = ProcessInfo.processInfo.arguments[0]
        if arg0.hasPrefix("/") { return arg0 }
        // Try to resolve relative path
        let cwd = FileManager.default.currentDirectoryPath
        let resolved = (cwd as NSString).appendingPathComponent(arg0)
        if FileManager.default.isExecutableFile(atPath: resolved) { return resolved }
        // Fallback
        return "/usr/local/bin/mocker"
    }
}

// MARK: - mocker socket uninstall

struct SocketUninstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Deactivate and remove the launchd socket agent"
    )

    func run() async throws {
        let config = MockerConfig()
        let uid = getuid()
        let label = MockerConfig.launchAgentLabel

        // Bootout
        let (_, exitCode) = try await runProcess(
            "/bin/launchctl",
            ["bootout", "gui/\(uid)", label]
        )

        // Remove plist file
        let plistPath = config.launchAgentPlistPath
        if FileManager.default.fileExists(atPath: plistPath) {
            try? FileManager.default.removeItem(atPath: plistPath)
        }

        // Remove socket file if present
        let sock = config.socketPath
        if FileManager.default.fileExists(atPath: sock) {
            try? FileManager.default.removeItem(atPath: sock)
        }

        if exitCode == 0 {
            print("Mocker socket agent uninstalled.")
        } else {
            print("Mocker socket agent removed (was not loaded or already removed).")
        }
    }
}

// MARK: - mocker socket status

struct SocketStatus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the status of the launchd socket agent"
    )

    func run() async throws {
        let config = MockerConfig()
        let sock = config.socketPath
        let plistPath = config.launchAgentPlistPath
        let label = MockerConfig.launchAgentLabel

        let plistExists = FileManager.default.fileExists(atPath: plistPath)
        let sockExists = FileManager.default.fileExists(atPath: sock)

        print("Label:       \(label)")
        print("Plist:       \(plistPath) [\(plistExists ? "installed" : "not installed")]")
        print("Socket:      \(sock) [\(sockExists ? "exists" : "not present")]")
        print("DOCKER_HOST: unix://\(sock)")

        // Check launchd status
        let (output, exitCode) = try await runProcess(
            "/bin/launchctl",
            ["list", label]
        )
        if exitCode == 0 {
            print("Agent:       loaded")
            if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print(output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else {
            print("Agent:       not loaded")
        }
    }
}

// MARK: - Helpers

private func runProcess(_ path: String, _ args: [String]) async throws -> (String, Int32) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    try p.run()
    return await withCheckedContinuation { continuation in
        p.terminationHandler = { proc in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            continuation.resume(returning: (out, proc.terminationStatus))
        }
    }
}
