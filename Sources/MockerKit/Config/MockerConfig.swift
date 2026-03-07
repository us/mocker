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

    /// Path for container metadata storage.
    public var containersPath: String { "\(dataRoot)/containers" }

    /// Path for image storage.
    public var imagesPath: String { "\(dataRoot)/images" }

    /// Path for volume storage.
    public var volumesPath: String { "\(dataRoot)/volumes" }

    /// Path for network metadata.
    public var networksPath: String { "\(dataRoot)/networks" }

    /// Ensure all required directories exist.
    public func ensureDirectories() throws {
        let fm = FileManager.default
        let dirs = [dataRoot, containersPath, imagesPath, volumesPath, networksPath]
        for dir in dirs {
            if !fm.fileExists(atPath: dir) {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }
    }
}
