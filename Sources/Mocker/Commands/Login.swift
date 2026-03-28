import ArgumentParser
import MockerKit
import Foundation

struct Login: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Authenticate to a registry"
    )

    @Option(name: .shortAndLong, help: "Username")
    var username: String?

    @Option(name: .shortAndLong, help: "Password or Personal Access Token")
    var password: String?

    @Flag(name: .long, help: "Take the password from stdin")
    var passwordStdin = false

    @Argument(help: "Registry server (default: Docker Hub)")
    var server: String = "https://index.docker.io/v1/"

    func run() async throws {
        // Registry authentication is not yet wired into pull/push operations.
        // Rather than silently storing credentials that are never used, fail explicitly.
        throw MockerError.operationFailed(
            "registry authentication is not yet supported by Mocker. " +
            "Pull/push operations use anonymous access only."
        )
    }
}
