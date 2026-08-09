import Testing
import Foundation
@testable import MockerKit

/// Networks used to be kept in a JSON file of mocker's own that the runtime knew nothing
/// about, so a compose project's `networks:` had no effect on any container. These tests
/// pin that every operation now goes to the real `container network` store.
@Suite("NetworkManager")
struct NetworkManagerTests {
    /// Shape of a real `container network ls --format json` response.
    private let listJSON = """
    [{"status":{"ipv4Gateway":"192.168.65.1","ipv4Subnet":"192.168.65.0/24"},
      "id":"shared","state":"running",
      "config":{"mode":"nat","labels":{"team":"infra"},"creationDate":807968813.820583,"id":"shared"}},
     {"status":{"ipv4Subnet":"192.168.64.0/24","ipv4Gateway":"192.168.64.1"},
      "id":"default","state":"running",
      "config":{"mode":"nat","id":"default","creationDate":807968261.978083,"labels":{}}}]
    """

    @Test("Listing maps the backend's JSON onto NetworkInfo")
    func parsesListing() {
        let networks = NetworkManager.parseNetworks(listJSON)

        #expect(networks.map(\.name) == ["default", "shared"])
        let shared = networks.first { $0.name == "shared" }
        #expect(shared?.subnet == "192.168.65.0/24")
        #expect(shared?.gateway == "192.168.65.1")
        #expect(shared?.driver == "nat")
        #expect(shared?.labels["team"] == "infra")
    }

    @Test("Malformed listing output yields no networks instead of throwing")
    func parsesGarbage() {
        #expect(NetworkManager.parseNetworks("not json").isEmpty)
        #expect(NetworkManager.parseNetworks("").isEmpty)
    }

    @Test("list shells out to the real network store")
    func listUsesBackend() async throws {
        let runner = MockProcessRunner(responses: [(listJSON, 0)])
        let manager = try NetworkManager(runner: runner, cli: "/usr/bin/container")

        let networks = try await manager.list()

        #expect(networks.count == 2)
        let calls = await runner.calls
        #expect(calls.first?.arguments == ["network", "ls", "--format", "json"])
    }

    @Test("create passes the name and an explicit subnet through")
    func createForwardsArguments() async throws {
        let runner = MockProcessRunner(responses: [("", 0), (listJSON, 0)])
        let manager = try NetworkManager(runner: runner, cli: "/usr/bin/container")

        _ = try? await manager.create(name: "shared", subnet: "192.168.65.0/24")

        let calls = await runner.calls
        #expect(calls.first?.arguments == ["network", "create", "--subnet", "192.168.65.0/24", "shared"])
    }

    @Test("A failed create reports the backend's own message")
    func createSurfacesBackendError() async throws {
        let runner = MockProcessRunner(responses: [("Error: network shared already exists", 1)])
        let manager = try NetworkManager(runner: runner, cli: "/usr/bin/container")

        await #expect(throws: MockerError.self) {
            _ = try await manager.create(name: "shared")
        }
    }

    @Test("remove deletes through the backend and returns what it removed")
    func removeUsesBackend() async throws {
        let runner = MockProcessRunner(responses: [(listJSON, 0), ("", 0)])
        let manager = try NetworkManager(runner: runner, cli: "/usr/bin/container")

        let removed = try await manager.remove("shared")

        #expect(removed.name == "shared")
        let calls = await runner.calls
        #expect(calls.last?.arguments == ["network", "delete", "shared"])
    }

    @Test("Inspecting an unknown network reports it as missing")
    func inspectUnknown() async throws {
        let runner = MockProcessRunner(responses: [(listJSON, 0)])
        let manager = try NetworkManager(runner: runner, cli: "/usr/bin/container")

        await #expect(throws: MockerError.self) {
            _ = try await manager.inspect("nope")
        }
    }

    @Test("connect and disconnect report that the runtime has no such operation")
    func connectUnsupported() async throws {
        let manager = try NetworkManager(runner: MockProcessRunner(), cli: "/usr/bin/container")

        await #expect(throws: MockerError.self) {
            try await manager.connect(container: "c", network: "n")
        }
        await #expect(throws: MockerError.self) {
            try await manager.disconnect(container: "c", network: "n")
        }
    }
}
