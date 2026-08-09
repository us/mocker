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

    private static let digests = [
        "sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc",
        "sha256:d9e8ff0000000000000000000000000000000000000000000000000000000000",
        "sha256:edf820e05c3374485390e7fe3669f1b6b429eda502a6d174a456647fb9ed26fe",
    ]

    @Test("A full digest matches exactly one image")
    func fullDigestMatchesOne() {
        #expect(ImageManager.matchingDigests(Self.digests[0], in: Self.digests) == [Self.digests[0]])
    }

    @Test("A bare hex prefix matches, with or without the algorithm prefix")
    func bareHexPrefixMatches() {
        // `mocker rmi d9e853e87e55` — the form `docker rmi` takes — used to match nothing.
        #expect(ImageManager.matchingDigests("d9e853e87e55", in: Self.digests) == [Self.digests[0]])
        #expect(ImageManager.matchingDigests("sha256:d9e853e87e55", in: Self.digests) == [Self.digests[0]])
    }

    @Test("A prefix shared by two images is reported as ambiguous, never picked")
    func ambiguousPrefix() {
        // `rmi` deletes; guessing between two images is the one thing it must not do.
        #expect(ImageManager.matchingDigests("d9e8", in: Self.digests).count == 2)
    }

    @Test("Several tags of one image are one match, not an ambiguity")
    func repeatedDigestIsOneImage() {
        let sameImageTwice = [Self.digests[0], Self.digests[0]]

        #expect(ImageManager.matchingDigests("d9e853", in: sameImageTwice) == [Self.digests[0]])
    }

    @Test("A prefix matching nothing yields nothing")
    func unknownPrefixMatchesNothing() {
        #expect(ImageManager.matchingDigests("ffff", in: Self.digests).isEmpty)
    }
}
