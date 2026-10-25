import Testing
import MockerKit
@testable import Mocker

/// `--filter` must behave like Docker's: an unknown key is an error, not a no-op.
/// Ignoring `dangling=true` made `rmi $(images -qf dangling=true)` delete every image.
@Suite("List filters")
struct ListFilterTests {

    private let images = [
        ImageInfo(id: "a", repository: "docker.io/library/alpine", tag: "3.20"),
        ImageInfo(id: "b", repository: "docker.io/library/alpine", tag: "latest"),
        ImageInfo(id: "c", repository: "mybuild", tag: "latest"),
        ImageInfo(id: "d", repository: "docker.io/library/0be91dde-ab34-4ed8-8b26-d4fb1ef97666", tag: "latest"),
    ]

    private func imageIDs(_ filter: String) throws -> [String] {
        try ImageLs.parse(["--filter", filter]).options.filtered(images).map(\.id)
    }

    @Test("an unknown key or a filter without `=` is rejected")
    func unknownKeyRejected() {
        #expect(throws: MockerError.self) { try imageIDs("foo=bar") }
        #expect(throws: MockerError.self) { try imageIDs("dangling") }
        #expect(throws: MockerError.self) { try ContainerLs.parse(["--filter", "foo=bar"]).options.filtered([]) }
    }

    @Test("images: dangling selects untagged (UUID-named) builds, the set image prune removes")
    func danglingMatchesPrune() throws {
        #expect(try imageIDs("dangling=true") == ["d"])
        #expect(try imageIDs("dangling=1") == ["d"])
        #expect(try imageIDs("dangling=false") == ["a", "b", "c"])
        // Any other value must fail, not fall through to every image.
        #expect(throws: MockerError.self) { try imageIDs("dangling=yes") }
    }

    @Test("images: reference matches a pulled image by its familiar name")
    func referenceMatchesFamiliarName() throws {
        #expect(try imageIDs("reference=alpine") == ["a", "b"])
        #expect(try imageIDs("reference=alpine:3.20") == ["a"])
        #expect(try imageIDs("reference=docker.io/library/alpine:latest") == ["b"])
        #expect(try imageIDs("reference=mybuild") == ["c"])
    }
}
