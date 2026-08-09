import Foundation
import Testing
import ArgumentParser
import MockerKit
@testable import Mocker

@Suite("NetworkInspect CLI Tests")
struct NetworkInspectCLITests {

    /// One `container network ls --format json` row, so these exercise the CLI mapping
    /// without touching the machine's real networks.
    private static let listJSON = """
    [{"status":{"ipv4Gateway":"10.0.0.1","ipv4Subnet":"10.0.0.0/8"},
      "id":"testnet","state":"running",
      "config":{"mode":"nat","labels":{},"creationDate":807968813.8,"id":"testnet"}}]
    """

    @Test("network inspect unknown target throws networkNotFound")
    func network_inspect_unknown_exits_one() async throws {
        let manager = try NetworkManager(runner: MockProcessRunner(responses: [("[]", 0)]))
        await #expect(throws: MockerError.self) {
            _ = try await inspectNetworks(targets: ["ghostnet"], manager: manager)
        }
    }

    @Test("network inspect single target emits JSON array with PascalCase keys")
    func network_inspect_single_emits_array() async throws {
        let manager = try NetworkManager(runner: MockProcessRunner(responses: [(Self.listJSON, 0)]))
        let results = try await inspectNetworks(targets: ["testnet"], manager: manager)
        #expect(results.count == 1)
        #expect(results[0].Name == "testnet")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let json = String(decoding: try encoder.encode(results), as: UTF8.self)
        #expect(json.hasPrefix("["))
        #expect(json.contains("\"Name\""))
    }

    @Test("--verbose flag is rejected (removed from Docker-compatible interface)")
    func verboseFlagRemoved() throws {
        #expect(throws: Error.self) { _ = try NetworkInspect.parse(["--verbose", "mynet"]) }
    }

    @Test("resolveKind maps .network to Kind.network")
    func resolveKindNetwork() {
        #expect(Inspect.resolveKind(type: .network) == .network)
    }
}
