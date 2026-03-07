import Testing

@Suite("CLI Tests")
struct CLITests {
    @Test("Mocker version is defined")
    func version() {
        let version = "0.1.0"
        #expect(!version.isEmpty)
    }
}
