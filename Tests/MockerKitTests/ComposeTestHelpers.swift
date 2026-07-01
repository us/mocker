import Foundation

/// Declarative temp-directory tree builder for compose project-directory tests.
enum ComposeTestHelpers {
    /// A single file to materialize relative to a fixture root.
    struct FileSpec {
        let path: String
        let content: String

        static func file(_ path: String, _ content: String) -> FileSpec {
            FileSpec(path: path, content: content)
        }
    }

    /// Builds a fresh temp directory tree containing the given files and returns its root URL.
    static func makeProjectDir(_ files: [FileSpec] = []) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for file in files {
            let url = root.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try file.content.write(to: url, atomically: true, encoding: .utf8)
        }

        return root
    }
}
