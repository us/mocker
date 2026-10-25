import Foundation

/// BuildKit's cache lives on the builder VM's disk, and `container` cannot prune part of
/// it. Docker's "remove build cache" therefore maps to deleting the builder; the next
/// `container build` starts a fresh one.
public enum BuildCache {
    /// Delete the builder and return the disk space its root filesystem occupied.
    public static func prune(runner: ProcessRunning = RealProcessRunner()) async throws -> UInt64 {
        let bytes = allocatedSize()
        let (output, status) = try await runner.run(
            executable: CLIResolver.resolve(), arguments: ["builder", "delete", "--force"]
        )
        // No builder means no cache: nothing to do, not a failure.
        guard status == 0 || output.localizedCaseInsensitiveContains("not found") else {
            throw MockerError.operationFailed(
                NetworkManager.errorMessage(from: output, fallback: "failed to delete the builder"))
        }
        return bytes
    }

    /// Bytes the builder's root filesystem image occupies on disk (it is a sparse file).
    static func allocatedSize() -> UInt64 {
        guard let root = MockerConfig.appleContainerStorePath() else { return 0 }
        let disk = root.appendingPathComponent("containers/buildkit/rootfs.ext4")
        let values = try? disk.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        return UInt64(values?.totalFileAllocatedSize ?? 0)
    }
}
