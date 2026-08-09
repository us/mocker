import Foundation

/// Global configuration for Mocker.
public struct MockerConfig: Codable, Sendable {
    public var dataRoot: String
    public var defaultRegistry: String

    public init(
        dataRoot: String? = nil,
        defaultRegistry: String = "docker.io"
    ) {
        self.dataRoot = dataRoot ?? MockerConfig.defaultDataRoot
        self.defaultRegistry = defaultRegistry
    }

    /// Default data root directory (~/.mocker).
    public static var defaultDataRoot: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.mocker"
    }

    /// OCI-compatible image store path used by Apple Containerization framework.
    ///
    /// Resolution order:
    ///   1. `MOCKER_OCI_STORE` env override (escape hatch)
    ///   2. Apple `container` CLI's store at `~/Library/Application Support/com.apple.container/`
    ///      when populated — keeps mocker's view consistent with the CLI.
    ///   3. Legacy `<dataRoot>/oci-store` (used only when Apple store is absent).
    ///
    /// Concurrency caveat: when sharing Apple's store, `state.json` writes from
    /// mocker and the `container` CLI are not protected by inter-process locking.
    /// Avoid running pull/remove/tag concurrently with the CLI.
    public var ociStorePath: URL {
        if let override = ProcessInfo.processInfo.environment["MOCKER_OCI_STORE"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        if let apple = Self.appleContainerStorePath() {
            return apple
        }
        return URL(fileURLWithPath: dataRoot).appendingPathComponent("oci-store")
    }

    /// Apple `container` CLI store root, or nil when not yet populated.
    /// Detection: `state.json` (regular file) or `content/` (directory) present.
    public static func appleContainerStorePath(
        fileManager: FileManager = .default,
        homeDirectory: String? = nil
    ) -> URL? {
        let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser.path
        let root = URL(fileURLWithPath: "\(home)/Library/Application Support/com.apple.container")

        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: root.appendingPathComponent("state.json").path,
                                  isDirectory: &isDir),
           !isDir.boolValue {
            return root
        }
        if fileManager.fileExists(atPath: root.appendingPathComponent("content").path,
                                  isDirectory: &isDir),
           isDir.boolValue {
            return root
        }
        return nil
    }

    /// Path for container metadata storage.
    public var containersPath: String { "\(dataRoot)/containers" }

    /// Path for volume storage.
    public var volumesPath: String { "\(dataRoot)/volumes" }

    /// Path for network metadata.

    /// Discover the Linux kernel binary installed by Apple's container CLI.
    public static var kernelPath: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let kernelsDir = "\(home)/Library/Application Support/com.apple.container/kernels"

        // Try the default kernel for the current architecture
        let arch = ProcessInfo.processInfo.machineHardwareName
        let isArm = arch.hasPrefix("arm") || arch == "arm64"
        let defaultName = isArm ? "default.kernel-arm64" : "default.kernel-amd64"
        let defaultPath = URL(fileURLWithPath: "\(kernelsDir)/\(defaultName)")

        if FileManager.default.fileExists(atPath: defaultPath.path) {
            return defaultPath
        }

        // Fallback: find any vmlinux in the kernels directory
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: kernelsDir) else { return nil }
        let kernel = files.filter { $0.hasPrefix("vmlinux") }.sorted().last
        if let kernel {
            return URL(fileURLWithPath: "\(kernelsDir)/\(kernel)")
        }
        return nil
    }

    /// vminit image reference used by ContainerManager to boot VMs.
    public static let vminitReference = "ghcr.io/apple/containerization/vminit:0.1.0"

    /// Directory for container log files.
    public var logsPath: String { "\(dataRoot)/logs" }

    /// Directory for port proxy PID files.
    public var proxiesPath: String { "\(dataRoot)/proxies" }

    /// Ensure all required directories exist.
    public func ensureDirectories() throws {
        let fm = FileManager.default
        let dirs = [dataRoot, containersPath, volumesPath, ociStorePath.path, logsPath, proxiesPath]
        for dir in dirs {
            if !fm.fileExists(atPath: dir) {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }
    }
}

extension ProcessInfo {
    var machineHardwareName: String {
        var sysInfo = utsname()
        uname(&sysInfo)
        return withUnsafePointer(to: &sysInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
