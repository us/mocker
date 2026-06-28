import Foundation
import Testing
import ArgumentParser
import MockerKit
@testable import Mocker

@Suite("NetworkInspect CLI Tests")
struct NetworkInspectCLITests {

    @Test("network inspect unknown target throws networkNotFound")
    func network_inspect_unknown_exits_one() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mocker-test-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        let config = MockerConfig(dataRoot: tempDir)
        try config.ensureDirectories()
        let manager = try NetworkManager(config: config)
        await #expect(throws: MockerError.self) {
            _ = try await inspectNetworks(targets: ["ghostnet"], manager: manager)
        }
    }

    @Test("network inspect single target emits JSON array with PascalCase keys")
    func network_inspect_single_emits_array() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mocker-test-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        let config = MockerConfig(dataRoot: tempDir)
        try config.ensureDirectories()
        let manager = try NetworkManager(config: config)
        _ = try await manager.create(name: "testnet", driver: "bridge", subnet: "10.0.0.0/8", gateway: "10.0.0.1")
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
