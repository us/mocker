import Testing
@testable import MockerKit

@Suite("ContainerEngine Tests")
struct ContainerEngineTests {

    @Test("Create throws unsupported error")
    func testCreateUnsupported() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()
        let engine = try ContainerEngine(config: config)
        let containerConfig = ContainerConfig(image: "alpine:latest")

        do {
            _ = try await engine.create(containerConfig)
            #expect(Bool(false), "create should have thrown")
        } catch {
            let msg = "\(error)"
            #expect(msg.contains("not supported"))
        }
    }

    @Test("Pause throws unsupported error")
    func testPauseUnsupported() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()
        let engine = try ContainerEngine(config: config)

        do {
            try await engine.pause("nonexistent")
            #expect(Bool(false), "pause should have thrown")
        } catch let error as MockerError {
            switch error {
            case .containerNotFound:
                break // Expected: container doesn't exist
            case .operationFailed(let msg):
                #expect(msg.contains("not supported"))
            default:
                #expect(Bool(false), "Unexpected error: \(error)")
            }
        }
    }

    @Test("Unpause throws unsupported error")
    func testUnpauseUnsupported() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()
        let engine = try ContainerEngine(config: config)

        do {
            try await engine.unpause("nonexistent")
            #expect(Bool(false), "unpause should have thrown")
        } catch let error as MockerError {
            switch error {
            case .containerNotFound:
                break // Expected
            case .operationFailed(let msg):
                #expect(msg.contains("not supported"))
            default:
                #expect(Bool(false), "Unexpected error: \(error)")
            }
        }
    }

    @Test("Rename throws unsupported error")
    func testRenameUnsupported() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()
        let engine = try ContainerEngine(config: config)

        do {
            try await engine.rename("nonexistent", to: "newname")
            #expect(Bool(false), "rename should have thrown")
        } catch let error as MockerError {
            switch error {
            case .containerNotFound:
                break // Expected
            case .operationFailed(let msg):
                #expect(msg.contains("not supported"))
            default:
                #expect(Bool(false), "Unexpected error: \(error)")
            }
        }
    }

    @Test("ContainerConfig default values")
    func testContainerConfigDefaults() {
        let config = ContainerConfig(image: "nginx:latest")
        #expect(config.image == "nginx:latest")
        #expect(config.command.isEmpty)
        #expect(config.environment.isEmpty)
        #expect(config.ports.isEmpty)
        #expect(config.rm == false)
        #expect(config.cidfile == nil)
        #expect(config.dnsSearch.isEmpty)
        #expect(config.dnsOption.isEmpty)
        #expect(config.interactive == false)
        #expect(config.tty == false)
    }

    @Test("ContainerConfig with all new fields")
    func testContainerConfigNewFields() {
        let config = ContainerConfig(
            image: "alpine",
            interactive: true,
            tty: true,
            memory: "512m",
            cpus: "2",
            cidfile: "/tmp/cid",
            rm: true,
            dnsSearch: ["example.com"],
            dnsOption: ["ndots:5"]
        )
        #expect(config.rm == true)
        #expect(config.cidfile == "/tmp/cid")
        #expect(config.dnsSearch == ["example.com"])
        #expect(config.dnsOption == ["ndots:5"])
        #expect(config.interactive == true)
        #expect(config.tty == true)
        #expect(config.memory == "512m")
        #expect(config.cpus == "2")
    }
}
