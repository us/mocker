import ArgumentParser
import Foundation

struct Version: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the Mocker version information"
    )

    // x-release-please-start-version
    static let currentVersion = "0.9.6"
    // x-release-please-end

    @Option(name: .shortAndLong, help: "Format output using a custom template")
    var format: String?

    func run() async throws {
        let object = Self.versionObject()

        if let format {
            let template = format == "json" ? "{{json .}}" : format
            print(try GoTemplate.render(template, object: object))
            return
        }

        // The text view reads the same record the templates see, so each value is set once.
        func field(_ side: String, _ key: String) -> String {
            ((object[side] as? [String: String]) ?? [:])[key] ?? ""
        }
        print("Client:")
        print(" Version:           \(field("Client", "Version"))")
        print(" API version:       \(field("Client", "ApiVersion"))")
        print(" OS/Arch:           \(field("Client", "Os"))/\(field("Client", "Arch"))")
        print(" Context:           mocker")
        print("")
        print("Server: Mocker Engine")
        print(" Version:          \(field("Server", "Version"))")
        print(" API version:      \(field("Server", "ApiVersion")) (minimum version 1.24)")
        print(" OS/Arch:          \(field("Server", "Os"))/\(field("Server", "Arch"))")
        print(" Runtime:          Apple Containerization")
    }

    /// Docker-shaped `version` record for `--format` templates (`{{.Client.Version}}`, ...).
    static func versionObject() -> [String: Any] {
        func side(_ os: String) -> [String: String] {
            ["Version": currentVersion, "ApiVersion": "1.47", "Os": os, "Arch": machineArch()]
        }
        return ["Client": side("darwin"), "Server": side("linux")]
    }

    private static func machineArch() -> String {
        #if arch(arm64)
        "arm64"
        #else
        "amd64"
        #endif
    }
}
