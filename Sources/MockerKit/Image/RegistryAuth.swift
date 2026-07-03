import Foundation
import ContainerizationOCI
import ContainerizationExtras

/// Registry credentials backed by the macOS keychain.
///
/// mocker owns its own keychain security domain: `mocker login` / `mocker logout`
/// manage entries here, and pull/push look them up automatically. This is separate
/// from Apple's `container` CLI keychain, because mocker pulls images through the
/// Containerization framework directly rather than shelling out to `container pull`.
public enum RegistryAuth {
    /// Keychain security domain that scopes all mocker registry credentials.
    static let securityDomain = "com.mocker.cli"

    private static var keychain: KeychainHelper {
        KeychainHelper(securityDomain: securityDomain)
    }

    /// Stored credentials for the registry hosting `reference`, or nil for anonymous access.
    /// `reference` should be a fully-qualified image reference (see `ImageManager.normalize`).
    public static func resolve(for reference: String) -> Authentication? {
        guard let host = try? Reference.parse(reference).resolvedDomain else { return nil }
        return try? keychain.lookup(hostname: host)
    }

    /// Verify credentials against the registry, then persist them to the keychain.
    public static func login(server: String, username: String, password: String) async throws {
        let host = hostname(for: server)
        let client = RegistryClient(
            host: host,
            authentication: BasicAuthentication(username: username, password: password),
            tlsConfiguration: TLSUtils.makeEnvironmentAwareTLSConfiguration()
        )
        try await client.ping()
        try keychain.save(hostname: host, username: username, password: password)
    }

    /// Remove stored credentials for `server`.
    public static func logout(server: String) throws {
        try keychain.delete(hostname: hostname(for: server))
    }

    /// Prompt stdin for a username (visible echo).
    public static func promptUsername(server: String) throws -> String {
        try keychain.userPrompt(hostname: server)
    }

    /// Prompt stdin for a password (echo disabled).
    public static func promptPassword() throws -> String {
        try keychain.passwordPrompt()
    }

    /// Reduce a user-supplied server (bare domain or full URL) to the keychain hostname,
    /// matching how pull/push resolve the host from an image reference. This keeps the
    /// `login` save key and the pull/push lookup key identical for Docker Hub, which the
    /// framework resolves `docker.io` → `registry-1.docker.io`.
    static func hostname(for server: String) -> String {
        var s = server
        if let scheme = s.range(of: "://") { s = String(s[scheme.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if s.isEmpty || s == "index.docker.io" { s = "docker.io" }
        return Reference.resolveDomain(domain: s)
    }
}
