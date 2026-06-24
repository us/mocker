import Testing
import ArgumentParser
@testable import Mocker

@Suite("ContainerInspect CLI Tests")
struct ContainerInspectCLITests {

    @Test("single target")
    func singleTarget() throws {
        let command = try ContainerInspect.parse(["abc"])
        #expect(command.containers == ["abc"])
    }

    @Test("multiple targets")
    func multipleTargets() throws {
        let command = try ContainerInspect.parse(["a", "b", "c"])
        #expect(command.containers == ["a", "b", "c"])
    }

    @Test("--format flag accepted")
    func formatFlagAccepted() throws {
        let command = try ContainerInspect.parse(["-f", "json", "abc"])
        #expect(command.format == "json")
        #expect(command.containers == ["abc"])
    }

    @Test("--size flag accepted")
    func sizeFlagAccepted() throws {
        let command = try ContainerInspect.parse(["--size", "abc"])
        #expect(command.size == true)
        #expect(command.containers == ["abc"])
    }

    @Test("--type rejected")
    func typeRejected() throws {
        #expect(throws: Error.self) {
            _ = try ContainerInspect.parse(["--type", "image", "abc"])
        }
    }

    @Test("--platform rejected")
    func platformRejected() throws {
        #expect(throws: Error.self) {
            _ = try ContainerInspect.parse(["--platform", "linux/amd64", "abc"])
        }
    }

    @Test("ContainerInspect registered under container group")
    func containerInspectRegisteredUnderContainerGroup() throws {
        let command = try ContainerCommand.parseAsRoot(["inspect", "abc"])
        guard let inspect = command as? ContainerInspect else {
            Issue.record("Expected ContainerInspect but got \(type(of: command))")
            return
        }
        #expect(inspect.containers == ["abc"])
    }
}
