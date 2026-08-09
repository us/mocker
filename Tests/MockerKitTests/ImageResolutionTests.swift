import Testing
import Foundation
@testable import MockerKit

@Suite("Image reference resolution order")
struct ImageResolutionTests {
    @Test("The literal reference is tried before the normalized one")
    func literalFirst() {
        let candidates = ImageManager.resolutionCandidates("caddy:latest")

        #expect(candidates.first == "caddy:latest")
        #expect(candidates.contains("docker.io/library/caddy:latest"))
    }

    @Test("A tag-less reference implies :latest before normalizing")
    func taglessImpliesLatest() {
        let candidates = ImageManager.resolutionCandidates("caddy")

        #expect(candidates.prefix(2) == ["caddy", "caddy:latest"])
        #expect(candidates.contains("docker.io/library/caddy:latest"))
    }

    @Test("An already-qualified reference resolves to itself first")
    func qualifiedReference() {
        let candidates = ImageManager.resolutionCandidates("docker.io/library/busybox:1.37")

        #expect(candidates.first == "docker.io/library/busybox:1.37")
    }

    @Test("No candidate is repeated")
    func candidatesAreUnique() {
        let candidates = ImageManager.resolutionCandidates("docker.io/library/alpine:3.20")

        #expect(Set(candidates).count == candidates.count)
    }

    @Test("A registry port is not mistaken for a tag")
    func registryPortIsNotATag() {
        #expect(ImageManager.hasTag("localhost:5000/app") == false)
        #expect(ImageManager.hasTag("localhost:5000/app:v1") == true)
        #expect(ImageManager.hasTag("alpine") == false)
        #expect(ImageManager.hasTag("alpine:3.20") == true)
        // A digest reference already pins the image; no `:latest` may be appended.
        #expect(ImageManager.hasTag("nginx@sha256:abc") == true)
    }

    @Test("Unknown size and creation date render as N/A, never as a measurement")
    func unknownMetadataRendersAsNA() {
        let unknown = ImageInfo(id: "sha256:abc", repository: "alpine", tag: "3.20")

        #expect(unknown.sizeString == "N/A")
        #expect(unknown.createdAgo == "N/A")
    }

    @Test("Known size and creation date are rendered normally")
    func knownMetadataRenders() {
        let known = ImageInfo(
            id: "sha256:abc",
            repository: "alpine",
            tag: "3.20",
            size: 22_731_608,
            created: Date(timeIntervalSinceNow: -3600)
        )

        #expect(known.sizeString != "N/A")
        #expect(known.sizeString.contains("MB"))
        #expect(known.createdAgo != "N/A")
    }

    @Test("An argument that looks like a digest is recognized", arguments: [
        "sha256:d9e853e87e55", "d9e853e87e55", "sha256:d9e8", "abcd",
    ])
    func digestFormsAreRecognized(reference: String) {
        // `mocker images -q` prints a truncated digest, and `images -q | xargs rmi` is
        // the usual cleanup, so these must be tried against stored digests.
        #expect(ImageManager.looksLikeDigest(reference))
    }

    @Test("Ordinary references are not mistaken for digests", arguments: [
        "alpine", "alpine:3.20", "docker.io/library/nginx:1.25", "sha256:", "abc", "",
    ])
    func namesAreNotDigests(reference: String) {
        #expect(!ImageManager.looksLikeDigest(reference))
    }

    @Test("A digest matches with or without the algorithm prefix")
    func digestBodyIgnoresAlgorithmPrefix() {
        // `docker rmi` takes the bare hex, `images -q` prints the prefixed form; both must
        // match the same stored digest.
        #expect(ImageManager.digestBody("sha256:d9e853") == "d9e853")
        #expect(ImageManager.digestBody("d9e853") == "d9e853")
        #expect(ImageManager.digestBody("sha256:d9e853").hasPrefix(ImageManager.digestBody("d9e8")))
    }
}
