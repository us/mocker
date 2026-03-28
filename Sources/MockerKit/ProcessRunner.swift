import Foundation

/// Protocol for running external CLI processes. Enables testing with mock implementations.
public protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String]) async throws -> (String, Int32)
}

/// Default implementation that runs real processes with safe pipe handling.
/// Reads stdout concurrently with process execution to avoid pipe-buffer deadlock
/// when output exceeds macOS's ~64KB pipe buffer.
public struct RealProcessRunner: ProcessRunning {
    public init() {}

    public func run(executable: String, arguments: [String]) async throws -> (String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Read stdout and stderr concurrently to prevent pipe-buffer deadlock.
        // If one pipe fills while the other isn't being drained, the child blocks.
        return await withCheckedContinuation { continuation in
            var outData = Data()
            var errData = Data()
            let group = DispatchGroup()

            group.enter()
            DispatchQueue.global().async {
                outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            group.enter()
            DispatchQueue.global().async {
                errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            group.notify(queue: .global()) {
                process.waitUntilExit()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
                let combined = out.isEmpty ? err : out
                continuation.resume(returning: (combined, process.terminationStatus))
            }
        }
    }
}

/// Mock implementation for unit testing. Captures arguments and returns preset output.
public actor MockProcessRunner: ProcessRunning {
    public struct Call: Sendable {
        public let executable: String
        public let arguments: [String]
    }

    private var _calls: [Call] = []
    private let _responses: [(String, Int32)]

    public var calls: [Call] { _calls }

    public init(responses: [(String, Int32)] = [("", 0)]) {
        self._responses = responses
    }

    public func run(executable: String, arguments: [String]) async throws -> (String, Int32) {
        _calls.append(Call(executable: executable, arguments: arguments))
        let idx = min(_calls.count - 1, _responses.count - 1)
        let response = _responses[max(0, idx)]
        return response
    }
}
