import ArgumentParser
import Foundation
import MockerKit

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run a Docker Engine API server on a Unix socket (DOCKER_HOST compatibility)"
    )

    @Option(name: .long, help: "Unix socket path (default: $HOME/.docker/run/docker.sock)")
    var socket: String?

    func run() async throws {
        let path = socket ?? Self.defaultSocketPath()
        let server = DockerAPIServer(socketPath: path, mockerVersion: Version.currentVersion)

        // Graceful shutdown: unlink the socket + stop NIO on Ctrl-C / SIGTERM.
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let stop: @Sendable () -> Void = { Task { await server.shutdown(); Foundation.exit(0) } }
        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        sigint.setEventHandler(handler: stop)
        sigterm.setEventHandler(handler: stop)
        sigint.resume()
        sigterm.resume()

        FileHandle.standardError.write(Data("""
        mocker serve — Docker Engine API \(DockerAPI.version) on \(path)
        Point tools at it:  export DOCKER_HOST=unix://\(path)
        Press Ctrl-C to stop.

        """.utf8))

        try await server.run()
    }

    static func defaultSocketPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.docker/run/docker.sock"
    }
}
