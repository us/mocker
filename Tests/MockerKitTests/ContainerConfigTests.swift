import Testing
@testable import MockerKit

@Suite("ContainerConfig Tests")
struct ContainerConfigTests {
    @Test("Parse valid port mapping")
    func parsePortMapping() throws {
        let mapping = try PortMapping.parse("8080:80")
        #expect(mapping.hostPort == 8080)
        #expect(mapping.containerPort == 80)
        #expect(mapping.portProtocol == .tcp)
    }

    @Test("Parse port mapping with protocol")
    func parsePortMappingWithProtocol() throws {
        let mapping = try PortMapping.parse("53:53/udp")
        #expect(mapping.hostPort == 53)
        #expect(mapping.containerPort == 53)
        #expect(mapping.portProtocol == .udp)
    }

    @Test("Parse invalid port mapping throws")
    func parseInvalidPortMapping() {
        #expect(throws: MockerError.self) {
            try PortMapping.parse("invalid")
        }
    }

    @Test("Parse bind mount volume")
    func parseBindMount() throws {
        let mount = try VolumeMount.parse("/host/data:/container/data")
        #expect(mount.source == "/host/data")
        #expect(mount.destination == "/container/data")
        #expect(mount.readOnly == false)
    }

    @Test("Parse read-only volume mount")
    func parseReadOnlyVolumeMount() throws {
        let mount = try VolumeMount.parse("/host/data:/container/data:ro")
        #expect(mount.source == "/host/data")
        #expect(mount.destination == "/container/data")
        #expect(mount.readOnly == true)
    }

    @Test("Parse named volume")
    func parseNamedVolume() throws {
        let mount = try VolumeMount.parse("mydata:/container/data")
        #expect(mount.source == "mydata")
        #expect(mount.destination == "/container/data")
        #expect(mount.readOnly == false)
    }

    @Test("Parse anonymous volume")
    func parseAnonymousVolume() throws {
        let mount = try VolumeMount.parse("/container/data")
        #expect(mount.source == "")
        #expect(mount.destination == "/container/data")
        #expect(mount.readOnly == false)
    }
}
