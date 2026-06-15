import Testing
import Foundation
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
}
