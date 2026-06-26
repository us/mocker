import Foundation
import Testing

@testable import MockerKit

@Suite("ContainerInspect Mapping Tests")
struct ContainerInspectMappingTests {

    /// A representative running container with a published port and labels.
    private func sampleInfo() -> ContainerInfo {
        ContainerInfo(
            id: "abc123def456",
            name: "web",
            image: "nginx:latest",
            state: .running,
            status: "Up",
            created: Date(timeIntervalSince1970: 1_700_000_000),
            ports: [PortMapping(hostPort: 8080, containerPort: 80, portProtocol: .tcp)],
            labels: ["com.example": "x"],
            command: "nginx -g daemon off;",
            pid: 4242,
            networkAddress: "192.168.64.3"
        )
    }

    @Test("Docker-shaped top-level fields")
    func topLevelFields() {
        let out = mapToContainerInspect(sampleInfo())
        #expect(out.id == "abc123def456")
        #expect(out.name == "/web")  // Docker prefixes with "/"
        #expect(out.image == "nginx:latest")
        #expect(out.created.hasPrefix("2023-11-14T"))  // RFC3339 string, not a number
    }

    @Test("State maps running container")
    func stateRunning() {
        let out = mapToContainerInspect(sampleInfo())
        #expect(out.state.status == "running")
        #expect(out.state.running == true)
        #expect(out.state.paused == false)
        #expect(out.state.dead == false)
        #expect(out.state.pid == 4242)
    }

    @Test("stopped state maps to Docker 'exited'")
    func stoppedMapsToExited() {
        var info = sampleInfo()
        info.state = .stopped
        info.pid = nil
        let out = mapToContainerInspect(info)
        #expect(out.state.status == "exited")  // Docker has no 'stopped'
        #expect(out.state.running == false)
        #expect(out.state.pid == 0)  // 0 when not running
    }

    @Test("Ports map uses Docker '<port>/<proto>' shape")
    func portsShape() {
        let out = mapToContainerInspect(sampleInfo())
        let binding = out.networkSettings.ports?["80/tcp"]?.first
        #expect(binding == ContainerInspectPortBinding(hostIp: "0.0.0.0", hostPort: "8080"))
        #expect(out.networkSettings.ipAddress == "192.168.64.3")
    }

    @Test("Config carries image, cmd and labels")
    func configFields() {
        let out = mapToContainerInspect(sampleInfo())
        #expect(out.config.image == "nginx:latest")
        #expect(out.config.cmd == ["nginx", "-g", "daemon", "off;"])
        #expect(out.config.labels == ["com.example": "x"])
    }

    @Test("Empty ports/labels/command are omitted, not empty objects")
    func absentFieldsOmitted() {
        var info = sampleInfo()
        info.ports = []
        info.labels = [:]
        info.command = ""
        let out = mapToContainerInspect(info)
        #expect(out.networkSettings.ports == nil)
        #expect(out.config.labels == nil)
        #expect(out.config.cmd == nil)
    }

    @Test("Serializes as a JSON array with Docker PascalCase keys")
    func jsonShape() throws {
        let out = mapToContainerInspect(sampleInfo())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = String(data: try encoder.encode([out]), encoding: .utf8)!
        #expect(json.hasPrefix("[") && json.hasSuffix("]"))  // single array, Docker parity
        #expect(json.contains("\"Id\":\"abc123def456\""))
        #expect(json.contains("\"Name\":\"/web\""))
        #expect(json.contains("\"State\":"))
        #expect(json.contains("\"NetworkSettings\":"))
        #expect(json.contains("\"80/tcp\""))
        #expect(!json.contains("\"status\""))  // not the internal lowercase shape
    }
}
