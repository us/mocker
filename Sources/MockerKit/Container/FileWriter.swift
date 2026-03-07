import Foundation
import Containerization

/// A `Containerization.Writer` that appends data to a log file on disk.
final class FileWriter: Containerization.Writer, @unchecked Sendable {
    private let fileHandle: FileHandle

    init(url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        self.fileHandle = try FileHandle(forWritingTo: url)
        fileHandle.seekToEndOfFile()
    }

    func write(_ data: Data) throws {
        fileHandle.write(data)
    }

    func close() throws {
        try fileHandle.close()
    }
}
