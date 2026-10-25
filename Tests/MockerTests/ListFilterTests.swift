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

    // `ps --filter ancestor=` — compared by digest, so however the container names its image.
    private let local = [
        ImageInfo(id: "sha256:d9e853e87e55", repository: "docker.io/library/alpine", tag: "3.20"),
        ImageInfo(id: "sha256:06d7adf3e0ef", repository: "docker.io/library/alpine", tag: "latest"),
        ImageInfo(id: "sha256:d9e8ff000000", repository: "ghcr.io/acme/app", tag: "1.0"),
        ImageInfo(id: "sha256:aaaa00000000", repository: "docker.io/myorg/alpine", tag: "latest"),
    ]

    private let containers = [
        ContainerInfo(id: "c1", name: "short", image: "alpine:3.20", state: .running, status: "Up", created: .now),
        ContainerInfo(id: "c2", name: "qualified", image: "docker.io/library/alpine:3.20", state: .running, status: "Up", created: .now),
        ContainerInfo(id: "c3", name: "latest", image: "alpine", state: .running, status: "Up", created: .now),
        ContainerInfo(id: "c4", name: "app", image: "ghcr.io/acme/app:1.0", state: .running, status: "Up", created: .now),
        ContainerInfo(id: "c5", name: "org", image: "myorg/alpine", state: .running, status: "Up", created: .now),
        ContainerInfo(id: "c6", name: "gone", image: "busybox:1.36", state: .exited, status: "Exited", created: .now),
    ]

    private func containerIDs(_ filter: String) throws -> [String] {
        try ContainerLs.parse(["--filter", filter]).options.filtered(containers, images: local).map(\.id)
    }

    @Test("ps: ancestor finds the image by ID, short name or qualified name alike")
    func ancestorMatchesByImage() throws {
        // `images -q` prints the ID; a container is recorded under whatever name started it.
        #expect(try containerIDs("ancestor=d9e853e87e55") == ["c1", "c2"])
        #expect(try containerIDs("ancestor=sha256:d9e853e87e55") == ["c1", "c2"])
        #expect(try containerIDs("ancestor=alpine:3.20") == ["c1", "c2"])
        #expect(try containerIDs("ancestor=docker.io/library/alpine:3.20") == ["c1", "c2"])
    }

    @Test("ps: a bare ancestor name means :latest, and a prefix is not a name")
    func ancestorIsNotAPrefixMatch() throws {
        #expect(try containerIDs("ancestor=alpine") == ["c3"])
        #expect(try containerIDs("ancestor=alp").isEmpty)
        #expect(try containerIDs("ancestor=nginx").isEmpty)
        // An ID prefix two images share names neither.
        #expect(try containerIDs("ancestor=d9e8").isEmpty)
    }
}

extension ListFilterTests {
    @Test("ps: ancestor names one image, never another repository with the same short name")
    func ancestorIsExactByName() throws {
        #expect(try containerIDs("ancestor=alpine") == ["c3"])
        #expect(try containerIDs("ancestor=myorg/alpine") == ["c5"])
        #expect(try containerIDs("ancestor=docker.io/myorg/alpine:latest") == ["c5"])
    }

    @Test("ps: a container whose image is gone is still found by the name it ran")
    func ancestorOfDeletedImage() throws {
        #expect(try containerIDs("ancestor=busybox:1.36") == ["c6"])
        #expect(try containerIDs("ancestor=busybox").isEmpty)
    }
}
