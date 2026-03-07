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

    /// OCI-compatible image store path (used by Apple Containerization framework).
    public var ociStorePath: URL {
        URL(fileURLWithPath: dataRoot).appendingPathComponent("oci-store")
    }

    /// Path for container metadata storage.
    public var containersPath: String { "\(dataRoot)/containers" }

    /// Path for volume storage.
    public var volumesPath: String { "\(dataRoot)/volumes" }

    /// Path for network metadata.
    public var networksPath: String { "\(dataRoot)/networks" }

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

    /// Ensure all required directories exist.
    public func ensureDirectories() throws {
        let fm = FileManager.default
        let dirs = [dataRoot, containersPath, volumesPath, networksPath, ociStorePath.path]
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
