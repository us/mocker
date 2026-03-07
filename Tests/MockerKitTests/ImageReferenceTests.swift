import Testing
@testable import MockerKit

@Suite("ImageReference Tests")
struct ImageReferenceTests {
    @Test("Parse simple image name")
    func parseSimple() throws {
        let ref = try ImageReference.parse("nginx")
        #expect(ref.registry == nil)
        #expect(ref.repository == "nginx")
        #expect(ref.tag == "latest")
    }

    @Test("Parse image with tag")
    func parseWithTag() throws {
        let ref = try ImageReference.parse("nginx:1.25")
        #expect(ref.registry == nil)
        #expect(ref.repository == "nginx")
        #expect(ref.tag == "1.25")
    }

    @Test("Parse image with registry")
    func parseWithRegistry() throws {
        let ref = try ImageReference.parse("registry.example.com/myapp:v1")
        #expect(ref.registry == "registry.example.com")
        #expect(ref.repository == "myapp")
        #expect(ref.tag == "v1")
    }

    @Test("Full reference string")
    func fullReference() throws {
        let ref = try ImageReference.parse("registry.example.com/myapp:v1")
        #expect(ref.fullReference == "registry.example.com/myapp:v1")
    }

    @Test("Parse empty throws")
    func parseEmpty() {
        #expect(throws: MockerError.self) {
            try ImageReference.parse("")
        }
    }
}
