import Testing
import Foundation
import ContainerizationOCI
@testable import MockerKit

// MARK: - Helpers

private func loadFixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: "Fixtures/image-inspect/\(name)", withExtension: nil) else {
        throw MockerError.operationFailed("Fixture not found: \(name)")
    }
    return try Data(contentsOf: url)
}

private func decodeManifest() throws -> ContainerizationOCI.Manifest {
    let data = try loadFixture("manifest.json")
    return try JSONDecoder().decode(ContainerizationOCI.Manifest.self, from: data)
}

private func decodeConfig() throws -> ContainerizationOCI.Image {
    let data = try loadFixture("config.json")
    return try JSONDecoder().decode(ContainerizationOCI.Image.self, from: data)
}

private func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    // Mirror the image-inspect CLI path, which emits slashes unescaped (Docker parity).
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
}

// MARK: - Test Suite

@Suite("ImageInspect Mapping Tests")
struct ImageInspectMappingTests {

    // Reference constants used across tests
    let taggedReference = "docker.io/library/nginx:latest"
    let indexDigest = "sha256:indexdigest0000000000000000000000000000000000000000000000000000"

    /// 2.1 — Golden fixture conformance: full byte-for-byte match against expected.json.
    @Test("Golden fixture: mapToImageInspect matches expected.json byte-for-byte")
    func goldenFixtureMatch() throws {
        let manifest = try decodeManifest()
        let config = try decodeConfig()
        let expected = try loadFixture("expected.json")

        let result = mapToImageInspect(
            config: config,
            manifest: manifest,
            reference: taggedReference,
            indexDigest: indexDigest
        )

        let encoded = try makeEncoder().encode(result)

        // Normalize both to comparable strings for a legible diff on failure
        let resultString = String(decoding: encoded, as: UTF8.self)
        let expectedString = String(decoding: expected, as: UTF8.self)
        #expect(resultString == expectedString)
    }

    /// 2.2 — Absent optional fields must be omitted (not null). Uses a minimal config with nil author.
    @Test("Absent Author field is omitted from JSON output")
    func absentAuthorOmitted() throws {
        let manifest = try decodeManifest()
        // Build a config with no author
        let configNoAuthor = ContainerizationOCI.Image(
            created: "2024-01-01T00:00:00Z",
            author: nil,
            architecture: "arm64",
            os: "linux",
            rootfs: ContainerizationOCI.Rootfs(type: "layers", diffIDs: ["sha256:aaa"])
        )

        let result = mapToImageInspect(
            config: configNoAuthor,
            manifest: manifest,
            reference: taggedReference,
            indexDigest: indexDigest
        )

        let encoded = try makeEncoder().encode(result)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(!json.contains("\"Author\""))
    }

    /// 2.3 — Digest-only reference must produce RepoTags == [] (present, not omitted).
    @Test("Digest-only reference produces empty RepoTags array")
    func digestOnlyReferenceEmptyRepoTags() throws {
        let manifest = try decodeManifest()
        let config = try decodeConfig()
        let digestOnlyRef = "docker.io/library/nginx@sha256:indexdigest0000000000000000000000000000000000000000000000000000"

        let result = mapToImageInspect(
            config: config,
            manifest: manifest,
            reference: digestOnlyRef,
            indexDigest: indexDigest
        )

        #expect(result.repoTags == [])
        let encoded = try makeEncoder().encode(result)
        let json = String(decoding: encoded, as: UTF8.self)
        // Key must still be present as empty array
        #expect(json.contains("\"RepoTags\" : ["))
    }

    /// 2.3b — Tag+digest reference must keep the `repo:tag` portion (everything before "@").
    @Test("Tag+digest reference produces RepoTags with the repo:tag portion")
    func tagAndDigestReferenceKeepsRepoTag() throws {
        let manifest = try decodeManifest()
        let config = try decodeConfig()
        let tagAndDigestRef = "docker.io/library/nginx:latest@sha256:indexdigest0000000000000000000000000000000000000000000000000000"

        let result = mapToImageInspect(
            config: config,
            manifest: manifest,
            reference: tagAndDigestRef,
            indexDigest: indexDigest
        )

        #expect(result.repoTags == ["docker.io/library/nginx:latest"])
    }

    /// 2.3c — Pure digest reference (no tag) must produce RepoTags == [].
    @Test("Pure digest reference produces empty RepoTags array")
    func pureDigestReferenceEmptyRepoTags() throws {
        let manifest = try decodeManifest()
        let config = try decodeConfig()
        let pureDigestRef = "docker.io/library/nginx@sha256:indexdigest0000000000000000000000000000000000000000000000000000"

        let result = mapToImageInspect(
            config: config,
            manifest: manifest,
            reference: pureDigestRef,
            indexDigest: indexDigest
        )

        #expect(result.repoTags == [])
    }

    /// 2.4 — Created must pass through as-is (RFC3339Nano string, not Double, not reformatted).
    @Test("Created is serialized as raw RFC3339Nano string, not a number")
    func createdPassThrough() throws {
        let manifest = try decodeManifest()
        let config = try decodeConfig()
        let expectedCreated = "2024-11-19T17:01:02.000000000Z"

        let result = mapToImageInspect(
            config: config,
            manifest: manifest,
            reference: taggedReference,
            indexDigest: indexDigest
        )

        #expect(result.created == expectedCreated)
        let encoded = try makeEncoder().encode(result)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(json.contains("\"Created\" : \"\(expectedCreated)\""))
    }

    /// 2.5 — Size must equal Σ manifest.layers[].size + manifest.config.size (no blob reads).
    @Test("Size equals sum of manifest layer sizes plus config size")
    func sizeComputation() throws {
        let manifest = try decodeManifest()
        let config = try decodeConfig()

        // Derived from fixture: layer1=3145728 + layer2=1048576 + config=7832 = 4202136
        let expectedSize: Int64 = 4202136

        let result = mapToImageInspect(
            config: config,
            manifest: manifest,
            reference: taggedReference,
            indexDigest: indexDigest
        )

        #expect(result.size == expectedSize)
    }

    /// 2.6 — RootFS.Layers must equal rootfs.diff_ids; Type must be "layers".
    @Test("RootFS.Layers matches OCI rootfs.diff_ids and Type is 'layers'")
    func rootFSMapping() throws {
        let manifest = try decodeManifest()
        let config = try decodeConfig()
        let expectedLayers = [
            "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        ]

        let result = mapToImageInspect(
            config: config,
            manifest: manifest,
            reference: taggedReference,
            indexDigest: indexDigest
        )

        #expect(result.rootFS.type == "layers")
        #expect(result.rootFS.layers == expectedLayers)
    }

    /// 2.7 — Config sub-object must use Docker PascalCase keys and mirror OCI config values.
    @Test("Config sub-object uses Docker PascalCase keys and mirrors OCI config values")
    func configMapping() throws {
        let manifest = try decodeManifest()
        let config = try decodeConfig()

        let result = mapToImageInspect(
            config: config,
            manifest: manifest,
            reference: taggedReference,
            indexDigest: indexDigest
        )

        let cfg = result.config
        #expect(cfg.cmd == ["nginx", "-g", "daemon off;"])
        #expect(cfg.env == [
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "NGINX_VERSION=1.27.0",
        ])
        #expect(cfg.workingDir == "/app")
        #expect(cfg.stopSignal == "SIGQUIT")
        #expect(cfg.labels == ["maintainer": "NGINX Docker Maintainers <docker-maint@nginx.com>"])
        // Encoded keys must be PascalCase
        let encoded = try makeEncoder().encode(result)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(json.contains("\"Cmd\""))
        #expect(json.contains("\"Env\""))
        #expect(json.contains("\"WorkingDir\""))
        #expect(json.contains("\"StopSignal\""))
        #expect(json.contains("\"Labels\""))
    }

    /// 2.8 — Config is always emitted; a config-less image yields `"Config": {}` (Docker parity).
    @Test("Config key is present as empty object when OCI config sub-object is absent")
    func configAbsentEmptyObject() throws {
        let manifest = try decodeManifest()
        let configNoConfig = ContainerizationOCI.Image(
            created: "2024-01-01T00:00:00Z",
            architecture: "arm64",
            os: "linux",
            config: nil,
            rootfs: ContainerizationOCI.Rootfs(type: "layers", diffIDs: ["sha256:aaa"])
        )

        let result = mapToImageInspect(
            config: configNoConfig,
            manifest: manifest,
            reference: taggedReference,
            indexDigest: indexDigest
        )

        let encoded = try makeEncoder().encode(result)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(json.contains("\"Config\" : {"))
        #expect(result.config.cmd == nil)
        #expect(result.config.env == nil)
    }
}
