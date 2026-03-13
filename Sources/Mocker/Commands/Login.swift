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
        let user: String
        if let u = username {
            user = u
        } else {
            print("Username: ", terminator: "")
            guard let u = readLine() else {
                throw MockerError.operationFailed("username required")
            }
            user = u
        }

        let pass: String
        if passwordStdin {
            guard let p = readLine() else {
                throw MockerError.operationFailed("password required")
            }
            pass = p
        } else if let p = password {
            pass = p
        } else {
            print("Password: ", terminator: "")
            guard let p = readLine() else {
                throw MockerError.operationFailed("password required")
            }
            pass = p
        }

        // Store credentials in Docker-compatible config.json
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mocker")
            .appendingPathComponent("config.json")

        var configDict: [String: Any] = [:]
        if let data = try? Data(contentsOf: configPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            configDict = existing
        }

        var auths = configDict["auths"] as? [String: Any] ?? [:]
        let authString = Data("\(user):\(pass)".utf8).base64EncodedString()
        auths[server] = ["auth": authString]
        configDict["auths"] = auths

        let data = try JSONSerialization.data(withJSONObject: configDict, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: configPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: configPath)

        print("Login Succeeded")
    }
}
