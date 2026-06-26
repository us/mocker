import Testing
import Foundation
@testable import MockerKit

@Suite("ContainerEngine.decodeInspect Tests")
struct ContainerEngineDecodeInspectTests {

    // MARK: - Helpers

    private func makeConfig(image: String = "alpine:latest") -> ContainerConfig {
        ContainerConfig(image: image)
    }

    private func makeDict(
        state: String? = "running",
        ipv4Address: String? = "10.0.0.1/24",
        networks: [[String: Any]]? = nil,
        configID: String = "abc123def456ghi"
    ) -> [String: Any] {
        var statusObj: [String: Any] = [:]
        if let state { statusObj["state"] = state }
        let nets: [[String: Any]]
        if let networks {
            nets = networks
        } else if let ip = ipv4Address {
            nets = [["ipv4Address": ip]]
        } else {
            nets = []
        }
        statusObj["networks"] = nets
        return [
            "configuration": ["id": configID] as [String: Any],
            "status": statusObj
        ]
    }

    // MARK: - Happy path

    @Test("decodeInspect running container with CIDR network returns running state and stripped IP")
    func decodeInspect_runningContainerWithCIDRNetwork_returnsRunningStateAndStrippedIP() {
        let dict = makeDict(state: "running", ipv4Address: "10.0.0.1/24")
        let config = makeConfig()
        let result = ContainerEngine.decodeInspect(dict, id: "fallback-id", name: "my-container", config: config)
        #expect(result != nil)
        #expect(result?.state == .running)
        #expect(result?.status == "Up Less than a second")
        #expect(result?.networkAddress == "10.0.0.1")
        #expect(result?.name == "my-container")
    }

    // MARK: - State mapping

    @Test("decodeInspect stopped state returns exited status")
    func decodeInspect_stoppedState_returnsExitedStatus() {
        let dict = makeDict(state: "stopped", ipv4Address: nil)
        let config = makeConfig()
        let result = ContainerEngine.decodeInspect(dict, id: "id1", name: "ctn", config: config)
        #expect(result?.state == .stopped)
        #expect(result?.status == ContainerState.exited.displayString)
    }

    @Test("decodeInspect unknown state falls back to running")
    func decodeInspect_unknownState_fallsBackToRunning() {
        let dict = makeDict(state: "paused", ipv4Address: nil)
        let config = makeConfig()
        let result = ContainerEngine.decodeInspect(dict, id: "id1", name: "ctn", config: config)
        #expect(result?.state == .running)
    }

    @Test("decodeInspect missing status key falls back to running and empty network")
    func decodeInspect_missingStatusKey_fallsBackToRunning() {
        let dict: [String: Any] = [
            "configuration": ["id": "abc"] as [String: Any]
        ]
        let config = makeConfig()
        let result = ContainerEngine.decodeInspect(dict, id: "fallback", name: "ctn", config: config)
        #expect(result?.state == .running)
        #expect(result?.networkAddress == "")
    }

    // MARK: - Network decode + CIDR

    @Test("decodeInspect plain IP returned as-is")
    func decodeInspect_plainIP_returnedAsIs() {
        let dict = makeDict(state: "running", ipv4Address: "10.0.0.1")
        let config = makeConfig()
        let result = ContainerEngine.decodeInspect(dict, id: "id1", name: "ctn", config: config)
        #expect(result?.networkAddress == "10.0.0.1")
    }

    @Test("decodeInspect multiple networks — first wins")
    func decodeInspect_multipleNetworks_firstWins() {
        let networks: [[String: Any]] = [
            ["ipv4Address": "10.0.0.1/24"],
            ["ipv4Address": "10.0.0.2/24"]
        ]
        let dict = makeDict(state: "running", ipv4Address: nil, networks: networks)
        let config = makeConfig()
        let result = ContainerEngine.decodeInspect(dict, id: "id1", name: "ctn", config: config)
        #expect(result?.networkAddress == "10.0.0.1")
    }

    @Test("decodeInspect empty networks array returns empty address")
    func decodeInspect_emptyNetworks_returnsEmptyAddress() {
        let dict = makeDict(state: "running", ipv4Address: nil, networks: [])
        let config = makeConfig()
        let result = ContainerEngine.decodeInspect(dict, id: "id1", name: "ctn", config: config)
        #expect(result?.networkAddress == "")
    }

    @Test("decodeInspect stopped container with network returns IP and exited state")
    func decodeInspect_stoppedContainerWithNetwork_returnsIPAndExitedState() {
        let dict = makeDict(state: "stopped", ipv4Address: "10.0.0.2/24")
        let config = makeConfig()
        let result = ContainerEngine.decodeInspect(dict, id: "id1", name: "ctn", config: config)
        #expect(result?.state == .stopped)
        #expect(result?.networkAddress == "10.0.0.2")
    }

    @Test("decodeInspect Compose regression — running container network address is non-empty")
    func decodeInspect_networkAddress_nonEmptyForRunningContainer() {
        let dict = makeDict(state: "running", ipv4Address: "172.16.0.5/16")
        let config = makeConfig()
        let result = ContainerEngine.decodeInspect(dict, id: "id1", name: "ctn", config: config)
        // Covers the Compose /etc/hosts injection contract: networkAddress must be non-empty
        // when the inspect blob carries a network, so injectServiceHostnames includes the container.
        #expect(result?.networkAddress != "")
        #expect(result?.networkAddress == "172.16.0.5")
    }

    // MARK: - Helper guard

    @Test("decodeInspect missing configuration key returns nil")
    func decodeInspect_missingConfigurationKey_returnsNil() {
        let dict: [String: Any] = ["status": ["state": "running"] as [String: Any]]
        let config = makeConfig()
        let result = ContainerEngine.decodeInspect(dict, id: "id1", name: "ctn", config: config)
        #expect(result == nil)
    }
}
