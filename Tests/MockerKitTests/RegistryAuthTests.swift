import Testing
import ContainerizationOCI
@testable import MockerKit

@Suite("RegistryAuth hostname resolution")
struct RegistryAuthTests {

    @Test("bare docker.io resolves to registry-1.docker.io")
    func dockerIoResolves() {
        #expect(RegistryAuth.hostname(for: "docker.io") == "registry-1.docker.io")
    }

    @Test("empty server defaults to Docker Hub")
    func emptyDefaultsToDockerHub() {
        #expect(RegistryAuth.hostname(for: "") == "registry-1.docker.io")
    }

    @Test("legacy v1 URL host maps to Docker Hub")
    func legacyURLMapsToDockerHub() {
        #expect(RegistryAuth.hostname(for: "https://index.docker.io/v1/") == "registry-1.docker.io")
    }

    @Test("third-party registry passes through")
    func thirdPartyPassesThrough() {
        #expect(RegistryAuth.hostname(for: "ghcr.io") == "ghcr.io")
    }

    @Test("registry with path keeps only the host")
    func stripsPath() {
        #expect(RegistryAuth.hostname(for: "ghcr.io/owner") == "ghcr.io")
    }

    /// The keychain lookup key used by pull/push (via a normalized reference) must match
    /// the save key used by `login` (via `hostname(for:)`), or credentials never resolve.
    @Test("login save key matches pull lookup key for Docker Hub")
    func loginKeyMatchesPullKey() throws {
        let loginKey = RegistryAuth.hostname(for: "docker.io")
        let pullKey = try ContainerizationOCI.Reference.parse("docker.io/library/alpine:latest").resolvedDomain
        #expect(loginKey == pullKey)
    }
}
