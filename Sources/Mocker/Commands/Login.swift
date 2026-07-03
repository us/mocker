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
    var server: String = "docker.io"

    func run() async throws {
        var username = self.username
        var password = self.password

        if passwordStdin {
            guard username != nil else {
                throw MockerError.operationFailed("Must provide --username with --password-stdin")
            }
            guard let data = try FileHandle.standardInput.readToEnd() else {
                throw MockerError.operationFailed("Failed to read password from stdin")
            }
            password = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let resolvedUser = try username ?? RegistryAuth.promptUsername(server: server)
        let resolvedPass: String
        if let password {
            resolvedPass = password
        } else {
            resolvedPass = try RegistryAuth.promptPassword()
            print()
        }

        try await RegistryAuth.login(server: server, username: resolvedUser, password: resolvedPass)
        print("Login succeeded")
    }
}
