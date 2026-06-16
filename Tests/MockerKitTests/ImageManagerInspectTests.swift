import Testing
import Foundation
import Containerization
import ContainerizationOCI
@testable import MockerKit

@Suite("ImageManager sole-manifest fallback")
struct ImageManagerInspectTests {

    private func descriptor(arch: String) -> ContainerizationOCI.Descriptor {
        ContainerizationOCI.Descriptor(
            mediaType: "application/vnd.oci.image.manifest.v1+json",
            digest: "sha256:\(arch)0000000000000000000000000000000000000000000000000000000000",
            size: 100,
            platform: ContainerizationOCI.Platform(arch: arch, os: "linux")
        )
    }

    private func image(
        reference: String,
        digest: String,
        contentStore: ContainerizationOCI.ContentStore
    ) -> Containerization.Image {
        let descriptor = ContainerizationOCI.Descriptor(
            mediaType: "application/vnd.oci.image.index.v1+json",
            digest: digest,
            size: 100
        )
        let description = Containerization.Image.Description(reference: reference, descriptor: descriptor)
        return Containerization.Image(description: description, contentStore: contentStore)
    }

    private func contentStore() throws -> ContainerizationOCI.ContentStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mocker-image-inspect-\(UUID().uuidString)")
        return try ContainerizationOCI.LocalContentStore(path: directory)
    }

    @Test("single-manifest index returns its sole descriptor")
    func singleManifestReturnsSole() {
        let sole = descriptor(arch: "amd64")
        #expect(ImageManager.soleManifestDescriptor(from: [sole]) == sole)
    }

    @Test("multi-manifest index returns nil (no implicit selection)")
    func multiManifestReturnsNil() {
        let manifests = [descriptor(arch: "amd64"), descriptor(arch: "arm64")]
        #expect(ImageManager.soleManifestDescriptor(from: manifests) == nil)
    }

    @Test("empty index returns nil")
    func emptyIndexReturnsNil() {
        #expect(ImageManager.soleManifestDescriptor(from: []) == nil)
    }

    @Test("repo metadata is derived from local references with the same descriptor")
    func repoMetadataUsesLocalAliases() throws {
        let store = try contentStore()
        let digest = "sha256:1111111111111111111111111111111111111111111111111111111111111111"
        let otherDigest = "sha256:2222222222222222222222222222222222222222222222222222222222222222"
        let inspected = image(reference: "docker.io/library/nginx:latest", digest: digest, contentStore: store)
        let localImages = [
            inspected,
            image(reference: "docker.io/library/nginx:1.25", digest: digest, contentStore: store),
            image(reference: "registry.example.com/prod/nginx:stable", digest: digest, contentStore: store),
            image(reference: "registry.example.com/other/nginx:latest", digest: otherDigest, contentStore: store),
        ]

        let metadata = ImageManager.repoMetadata(
            for: inspected,
            localImages: localImages,
            fallbackReference: "docker.io/library/not-used:latest"
        )

        #expect(metadata.tags == [
            "docker.io/library/nginx:1.25",
            "docker.io/library/nginx:latest",
            "registry.example.com/prod/nginx:stable",
        ])
        #expect(metadata.digests == [
            "docker.io/library/nginx@\(digest)",
            "registry.example.com/prod/nginx@\(digest)",
        ])
    }

    @Test("digest-only local reference leaves RepoTags empty")
    func repoMetadataDigestOnlyReference() throws {
        let store = try contentStore()
        let digest = "sha256:3333333333333333333333333333333333333333333333333333333333333333"
        let inspected = image(reference: "docker.io/library/nginx@\(digest)", digest: digest, contentStore: store)

        let metadata = ImageManager.repoMetadata(
            for: inspected,
            localImages: [inspected],
            fallbackReference: "docker.io/library/not-used:latest"
        )

        #expect(metadata.tags == [])
        #expect(metadata.digests == ["docker.io/library/nginx@\(digest)"])
    }

    @Test("tag plus digest local reference strips digest from RepoTags")
    func repoMetadataTagAndDigestReference() throws {
        let store = try contentStore()
        let digest = "sha256:4444444444444444444444444444444444444444444444444444444444444444"
        let inspected = image(reference: "docker.io/library/nginx:latest@\(digest)", digest: digest, contentStore: store)

        let metadata = ImageManager.repoMetadata(
            for: inspected,
            localImages: [inspected],
            fallbackReference: "docker.io/library/not-used:latest"
        )

        #expect(metadata.tags == ["docker.io/library/nginx:latest"])
        #expect(metadata.digests == ["docker.io/library/nginx@\(digest)"])
    }
}
