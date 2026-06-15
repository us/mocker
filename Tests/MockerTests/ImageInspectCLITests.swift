import Testing
import ArgumentParser
@testable import Mocker

@Suite("ImageInspect CLI Tests")
struct ImageInspectCLITests {

    // MARK: - Inspect --type routing

    @Test("--type image routes to image inspect")
    func typeImageIsImage() throws {
        let command = try Inspect.parse(["--type", "image", "nginx"])
        #expect(command.type == "image")
    }

    @Test("--type container routes to container inspect")
    func typeContainerIsContainer() throws {
        let command = try Inspect.parse(["--type", "container", "nginx"])
        #expect(command.type == "container")
    }

    @Test("omitting --type leaves type nil (container-first fallback)")
    func typeNilWhenOmitted() throws {
        let command = try Inspect.parse(["nginx"])
        #expect(command.type == nil)
    }

    // MARK: - Inspect.resolveKind routing decision

    @Test("resolveKind maps type=image to .image")
    func resolveKindImage() {
        #expect(Inspect.resolveKind(type: "image") == .image)
    }

    @Test("resolveKind maps type=container to .container")
    func resolveKindContainer() {
        #expect(Inspect.resolveKind(type: "container") == .container)
    }

    @Test("resolveKind maps nil type to .auto (container-first)")
    func resolveKindAuto() {
        #expect(Inspect.resolveKind(type: nil) == .auto)
    }

    // MARK: - ImageInspect --platform

    @Test("--platform is forwarded to ImageInspect command")
    func platformOptionParsed() throws {
        let command = try ImageInspect.parse(["--platform", "linux/amd64", "nginx"])
        #expect(command.platform == "linux/amd64")
    }
}
