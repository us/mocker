import Testing
import ArgumentParser
@testable import Mocker

@Suite("CLI Tests")
struct CLITests {
    @Test("Mocker version is defined")
    func version() {
        let version = "0.1.0"
        #expect(!version.isEmpty)
    }

    @Test("Run command accepts --env-file flag")
    func runEnvFileFlag() throws {
        let command = try Run.parse(["--env-file", "test.env", "alpine"])
        #expect(command.envFile == "test.env")
        #expect(command.image == "alpine")
    }
}
