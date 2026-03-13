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
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mocker")
            .appendingPathComponent("config.json")

        guard let data = try? Data(contentsOf: configPath),
              var configDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var auths = configDict["auths"] as? [String: Any] else {
            print("Not logged in to \(server)")
            return
        }

        if auths.removeValue(forKey: server) != nil {
            configDict["auths"] = auths
            let updatedData = try JSONSerialization.data(withJSONObject: configDict, options: [.prettyPrinted, .sortedKeys])
            try updatedData.write(to: configPath)
            print("Removing login credentials for \(server)")
        } else {
            print("Not logged in to \(server)")
        }
    }
}
