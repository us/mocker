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

        // Drain both pipes concurrently: if one fills while the other is not being read,
        // the child blocks on write and never exits.
        let outHandle = stdoutPipe.fileHandleForReading
        let errHandle = stderrPipe.fileHandleForReading
        let outTask = Task.detached { outHandle.readDataToEndOfFile() }
        let errTask = Task.detached { errHandle.readDataToEndOfFile() }

        try process.run()

        // Exit is observed through `terminationHandler` rather than `waitUntilExit()`:
        // the blocking call can wedge a thread that Swift concurrency needed, which
        // deadlocked commands that shell out several times (compose down).
        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
        }

        let out = String(data: await outTask.value, encoding: .utf8) ?? ""
        let err = String(data: await errTask.value, encoding: .utf8) ?? ""
        return (out.isEmpty ? err : out, status)
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
