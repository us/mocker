import Foundation
import Testing

@testable import MockerKit

@Suite("NetworkInspect Mapping Tests")
struct NetworkInspectMappingTests {

    private func sampleInfo() -> NetworkInfo {
        NetworkInfo(
            id: "abc123def456789012345678901234567890abcd",
            name: "mynet",
            driver: "bridge",
            subnet: "192.168.64.0/24",
            gateway: "192.168.64.1",
            containers: [],
            created: Date(timeIntervalSince1970: 1_748_779_200),
            labels: ["env": "test"]
        )
    }

    @Test("Top-level fields map from NetworkInfo")
    func topLevelFields() {
        let out = mapToNetworkInspect(sampleInfo())
        #expect(out.Name == "mynet")
        #expect(out.Id == "abc123def456789012345678901234567890abcd")
        #expect(out.Driver == "bridge")
        #expect(out.Scope == "local")
        #expect(out.Created.hasPrefix("2025-06-01"))
    }

    @Test("Constant fields emit correct literals")
    func constantFields() {
        let out = mapToNetworkInspect(sampleInfo())
        #expect(out.EnableIPv4 == true)
        #expect(out.EnableIPv6 == false)
        #expect(out.Internal == false)
        #expect(out.Attachable == false)
        #expect(out.Ingress == false)
        #expect(out.ConfigOnly == false)
    }

    @Test("IPAM with subnet and gateway produces one Config entry")
    func ipamWithSubnet() {
        let out = mapToNetworkInspect(sampleInfo())
        #expect(out.IPAM.Driver == "default")
        #expect(out.IPAM.Options == nil)
        #expect(out.IPAM.Config.count == 1)
        #expect(out.IPAM.Config[0].Subnet == "192.168.64.0/24")
        #expect(out.IPAM.Config[0].Gateway == "192.168.64.1")
    }

    @Test("IPAM with empty subnet produces empty Config array")
    func ipamEmptySubnet() {
        var info = sampleInfo()
        info.subnet = nil; info.gateway = nil
        let out = mapToNetworkInspect(info)
        #expect(out.IPAM.Config.isEmpty)
    }

    @Test("Containers is always an empty map")
    func containersAlwaysEmpty() {
        var info = sampleInfo()
        info.containers = ["web", "db"]
        #expect(mapToNetworkInspect(info).Containers == [:])
    }

    @Test("Options is always an empty map")
    func optionsAlwaysEmpty() {
        #expect(mapToNetworkInspect(sampleInfo()).Options == [:])
    }

    @Test("Labels map directly from NetworkInfo")
    func labelsDirectMapping() {
        #expect(mapToNetworkInspect(sampleInfo()).Labels == ["env": "test"])
    }

    @Test("Labels are empty map when NetworkInfo has no labels")
    func labelsEmptyWhenNone() {
        var info = sampleInfo(); info.labels = [:]
        #expect(mapToNetworkInspect(info).Labels == [:])
    }

    @Test("ConfigFrom always present with empty Network string")
    func configFromAlwaysPresent() {
        #expect(mapToNetworkInspect(sampleInfo()).ConfigFrom.Network == "")
    }

    @Test("Empty gateway string produces no Gateway key in IPAM Config")
    func emptyGatewayOmitted() {
        var info = sampleInfo(); info.gateway = ""
        let out = mapToNetworkInspect(info)
        #expect(out.IPAM.Config.count == 1)
        #expect(out.IPAM.Config[0].Gateway == nil)
    }

    @Test("JSON shape: PascalCase keys, array wrap, Options null, Containers {}")
    func jsonShape() throws {
        let out = mapToNetworkInspect(sampleInfo())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode([out])
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.hasPrefix("["))
        #expect(json.hasSuffix("]"))
        #expect(json.contains("\"Name\""))
        #expect(json.contains("\"IPAM\""))
        #expect(json.contains("\"Containers\""))
        #expect(json.contains("\"Options\" : null"))
        #expect(json.contains("\"Containers\" : {"))
        #expect(!json.contains("\\/"))
        #expect(!json.contains("\"name\""))
    }

    @Test("Golden fixture: mapToNetworkInspect matches expected-bridge.json")
    func goldenFixture() throws {
        guard let url = Bundle.module.url(
            forResource: "Fixtures/network-inspect/expected-bridge",
            withExtension: "json"
        ) else {
            Issue.record("Fixture not found: expected-bridge.json"); return
        }
        let expected = try String(contentsOf: url, encoding: .utf8)
        var info = sampleInfo(); info.name = "bridge"; info.labels = [:]
        let data = try { () -> Data in
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return try e.encode(mapToNetworkInspect(info))
        }()
        func normalize(_ s: String) throws -> String {
            let d = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: Data(s.utf8)), options: [.sortedKeys])
            return String(decoding: d, as: UTF8.self)
        }
        #expect(try normalize(String(decoding: data, as: UTF8.self)) == normalize(expected))
    }
}
