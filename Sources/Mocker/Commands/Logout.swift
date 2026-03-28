import ArgumentParser
import MockerKit
import Foundation

struct Logout: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Log out from a registry"
    )

    @Argument(help: "Registry server (default: Docker Hub)")
    var server: String = "https://index.docker.io/v1/"

    func run() async throws {
        throw MockerError.operationFailed(
            "registry authentication is not yet supported by Mocker. " +
            "Pull/push operations use anonymous access only."
        )
    }
}
