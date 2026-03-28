import Testing
@testable import MockerKit

@Suite("Flag Enforcement Tests")
struct FlagEnforcementTests {

    @Test("PortMapping parse valid mapping")
    func testPortMappingParse() throws {
        let pm = try PortMapping.parse("8080:80")
        #expect(pm.hostPort == 8080)
        #expect(pm.containerPort == 80)
        #expect(pm.portProtocol == .tcp)
    }

    @Test("PortMapping parse with protocol")
    func testPortMappingWithProtocol() throws {
        let pm = try PortMapping.parse("5353:53/udp")
        #expect(pm.hostPort == 5353)
        #expect(pm.containerPort == 53)
        #expect(pm.portProtocol == .udp)
    }

    @Test("VolumeMount parse bind mount")
    func testVolumeMountBind() throws {
        let vm = try VolumeMount.parse("/host/path:/container/path")
        #expect(vm.source == "/host/path")
        #expect(vm.destination == "/container/path")
        #expect(vm.readOnly == false)
    }

    @Test("VolumeMount parse read-only")
    func testVolumeMountReadOnly() throws {
        let vm = try VolumeMount.parse("/host:/container:ro")
        #expect(vm.readOnly == true)
    }

    @Test("VolumeMount parse anonymous volume")
    func testVolumeMountAnonymous() throws {
        let vm = try VolumeMount.parse("/data")
        #expect(vm.source == "")
        #expect(vm.destination == "/data")
    }

    @Test("RestartPolicy raw values match Docker")
    func testRestartPolicies() {
        #expect(RestartPolicy.no.rawValue == "no")
        #expect(RestartPolicy.always.rawValue == "always")
        #expect(RestartPolicy.onFailure.rawValue == "on-failure")
        #expect(RestartPolicy.unlessStopped.rawValue == "unless-stopped")
    }

    @Test("MockProcessRunner captures calls")
    func testMockProcessRunner() async throws {
        let mock = MockProcessRunner(responses: [("output-1", 0), ("output-2", 0)])
        let (out1, code1) = try await mock.run(executable: "/usr/bin/ls", arguments: ["-la"])
        let (out2, code2) = try await mock.run(executable: "/usr/bin/cat", arguments: ["file.txt"])

        #expect(out1 == "output-1")
        #expect(code1 == 0)
        #expect(out2 == "output-2")
        #expect(code2 == 0)
        let calls = await mock.calls
        #expect(calls.count == 2)
        #expect(calls[0].executable == "/usr/bin/ls")
        #expect(calls[1].arguments == ["file.txt"])
    }
}
