import ArgumentParser
import Foundation

struct Version: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the Mocker version information"
    )

    static let currentVersion = "0.2.0"

    @Option(name: .shortAndLong, help: "Format output using a custom template")
    var format: String?

    func run() async throws {
        let ver = Self.currentVersion

        if let format {
            var output = format
            output = output.replacingOccurrences(of: "{{.Client.Version}}", with: ver)
            output = output.replacingOccurrences(of: "{{.Server.Version}}", with: ver)
            output = output.replacingOccurrences(of: "{{.Client.Os}}", with: "darwin")
            output = output.replacingOccurrences(of: "{{.Client.Arch}}", with: machineArch())
            print(output)
        } else {
            print("Client:")
            print(" Version:           \(ver)")
            print(" API version:       1.47")
            print(" OS/Arch:           darwin/\(machineArch())")
            print(" Context:           mocker")
            print("")
            print("Server: Mocker Engine")
            print(" Version:          \(ver)")
            print(" API version:      1.47 (minimum version 1.24)")
            print(" OS/Arch:          linux/\(machineArch())")
            print(" Runtime:          Apple Containerization")
        }
    }

    private func machineArch() -> String {
        #if arch(arm64)
        "arm64"
        #else
        "amd64"
        #endif
    }
}
