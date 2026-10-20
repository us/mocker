import Testing
@testable import MockerKit

/// `platform:` on a service must survive parsing and take part in the config hash,
/// so that changing it recreates the container on the next `up`.
@Suite("Compose service platform")
struct ComposePlatformTests {

    private func parse(_ platformLine: String) throws -> ComposeService {
        let yaml = """
        services:
          web:
            image: nginx
        \(platformLine)
        """
        let compose = try ComposeFile.parse(yaml)
        return try #require(compose.services["web"])
    }

    @Test("platform: is parsed from the service definition")
    func platformParsed() throws {
        #expect(try parse("    platform: linux/amd64").platform == "linux/amd64")
    }

    @Test("changing platform changes the service config hash")
    func platformAffectsHash() throws {
        let amd64 = try parse("    platform: linux/amd64")
        let arm64 = try parse("    platform: linux/arm64")
        let none = try parse("")
        #expect(ComposeService.hash(of: amd64) != ComposeService.hash(of: arm64))
        #expect(ComposeService.hash(of: amd64) != ComposeService.hash(of: none))
    }
}
