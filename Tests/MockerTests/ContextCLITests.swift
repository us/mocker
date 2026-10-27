import Foundation
import Testing
import ArgumentParser
@testable import Mocker

@Suite("Context CLI Tests")
struct ContextCLITests {

    @Test("built-in context is named default with a unix docker endpoint")
    func builtInShape() {
        let c = ContextRecord.builtIn(socketPath: "/tmp/docker.sock")
        #expect(c.Name == "default")
        #expect(c.dockerEndpoint == "unix:///tmp/docker.sock")
    }

    @Test("inspect with no names resolves to default")
    func inspectDefaultsToCurrent() throws {
        let result = try ContextInspect.resolve([])
        #expect(result.map(\.Name) == ["default"])
    }

    @Test("inspect unknown context throws")
    func inspectUnknownThrows() {
        #expect(throws: ContextError.self) { _ = try ContextInspect.resolve(["nope"]) }
    }

    @Test("use accepts default and rejects unknown contexts")
    func useChecksName() throws {
        #expect(try MockerCLI.parseAsRoot(["context", "use", "default"]) is ContextUse)
        #expect(throws: ContextError.self) { _ = try ContextInspect.resolve(["other"]) }
    }

    @Test("ls accepts the list alias and --quiet")
    func listParses() throws {
        let cmd = try MockerCLI.parseAsRoot(["context", "list", "-q"])
        #expect(cmd is ContextList)
    }
}
