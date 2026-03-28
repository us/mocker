import Testing
import ArgumentParser
@testable import Mocker

@Suite("CLI Tests")
struct CLITests {
    @Test("Mocker version is defined and consistent")
    func version() {
        let version = Version.currentVersion
        #expect(!version.isEmpty)
        #expect(version == "0.2.0")
    }

    @Test("Run command accepts --env-file flag")
    func runEnvFileFlag() throws {
        let command = try Run.parse(["--env-file", "test.env", "alpine"])
        #expect(command.envFile == "test.env")
        #expect(command.image == "alpine")
    }
}
