import ArgumentParser
import MockerKit
import Foundation

struct Logout: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Log out from a registry"
    )

    @Argument(help: "Registry server (default: Docker Hub)")
    var server: String = "docker.io"

    func run() async throws {
        try RegistryAuth.logout(server: server)
        print("Removed login credentials for \(server)")
    }
}
