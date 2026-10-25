import Testing
@testable import MockerKit

/// `ImageManager.pruneCandidates` — the pure selection behind `image prune` and
/// `system prune`. Docker semantics: dangling = unnamed (here: a UUID-named untagged
/// build), `--all` = every image no container uses; the runtime's own images never.
@Suite("ImageManager prune candidates")
struct ImageManagerPruneTests {

    private let untaggedBuild = ImageInfo(
        id: "sha256:aaa1", repository: "docker.io/library/0be91dde-ab34-4ed8-8b26-d4fb1ef97666", tag: "latest")
    private let alpine = ImageInfo(id: "sha256:bbb2", repository: "docker.io/library/alpine", tag: "3.20")
    private let app = ImageInfo(id: "sha256:ccc3", repository: "ghcr.io/acme/app", tag: "1.0")
    private let vminit = ImageInfo(id: "sha256:ddd4", repository: "ghcr.io/apple/containerization/vminit", tag: "0.47.0")
    private let shim = ImageInfo(id: "sha256:eee5", repository: "ghcr.io/apple/container-builder-shim/builder", tag: "0.13.2")
    private var all: [ImageInfo] { [untaggedBuild, alpine, app, vminit, shim] }

    @Test("without --all only untagged (UUID-named) builds are dangling")
    func danglingOnly() {
        #expect(ImageManager.pruneCandidates(all, all: false, inUse: []).map(\.id) == ["sha256:aaa1"])
    }

    @Test("--all removes every image no container uses, however the container spells it")
    func allUnused() {
        #expect(ImageManager.pruneCandidates(all, all: true, inUse: []).map(\.id) == ["sha256:aaa1", "sha256:bbb2", "sha256:ccc3"])
        #expect(ImageManager.pruneCandidates(all, all: true, inUse: ["alpine:3.20", "ghcr.io/acme/app:1.0"]).map(\.id) == ["sha256:aaa1"])
        // By ID prefix, and by the fully-qualified name a pull stores.
        #expect(ImageManager.pruneCandidates(all, all: true, inUse: ["bbb2", "docker.io/library/alpine:3.20"]).map(\.id) == ["sha256:aaa1", "sha256:ccc3"])
    }

    @Test("an untagged build a container still uses is not dangling-pruned")
    func danglingInUseKept() {
        #expect(ImageManager.pruneCandidates(all, all: false, inUse: ["sha256:aaa1"]).isEmpty)
        #expect(ImageManager.pruneCandidates(all, all: false, inUse: [untaggedBuild.reference]).isEmpty)
    }

    @Test("the runtime's own images are never candidates")
    func runtimeImagesKept() {
        let ids = ImageManager.pruneCandidates(all, all: true, inUse: []).map(\.id)
        #expect(!ids.contains("sha256:ddd4"))
        #expect(!ids.contains("sha256:eee5"))
    }
}

@Suite("ContainerEngine images in use")
struct ContainerEngineImagesInUseTests {

    @Test("reference and digest come from each `container ls --format json` entry")
    func imageReferences() {
        let entries: [[String: Any]] = [
            ["configuration": ["image": [
                "reference": "docker.io/library/alpine:3.20",
                "descriptor": ["digest": "sha256:d9e8"],
            ]]],
            ["configuration": [:]],
        ]
        #expect(ContainerEngine.imageReferences(in: entries) == ["docker.io/library/alpine:3.20", "sha256:d9e8"])
    }
}
