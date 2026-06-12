import Testing
import Foundation
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
        #expect(config.virtualization == false)
        #expect(config.kernel == nil)
    }

    @Test("ContainerConfig with all new fields")
    func testContainerConfigNewFields() {
        let config = ContainerConfig(
            image: "alpine",
            interactive: true,
            tty: true,
            virtualization: true,
            kernel: "/tmp/vmlinux",
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
        #expect(config.virtualization == true)
        #expect(config.kernel == "/tmp/vmlinux")
    }

    @Test("Run arguments include nested virtualization flags")
    func testRunArgumentsIncludeVirtualizationFlags() {
        let config = ContainerConfig(
            image: "ubuntu:latest",
            command: ["sh", "-c", "dmesg | grep kvm"],
            virtualization: true,
            kernel: "/path/to/kernel"
        )

        let args = ContainerEngine.buildRunArguments(name: "nested-virtualization", config: config)

        #expect(args.contains("--virtualization"))
        #expect(args.contains("--kernel"))
        #expect(args.contains("/path/to/kernel"))
    }

    @Test("Run arguments publish TCP ports natively with -p")
    func testRunArgumentsPublishTCPPort() {
        let config = ContainerConfig(
            image: "nginx:alpine",
            ports: [PortMapping(hostPort: 18081, containerPort: 80)]
        )

        let args = ContainerEngine.buildRunArguments(name: "web", config: config)

        let idx = args.firstIndex(of: "-p")
        #expect(idx != nil)
        if let idx { #expect(args[idx + 1] == "18081:80/tcp") }
    }

    @Test("Run arguments publish UDP ports with protocol suffix")
    func testRunArgumentsPublishUDPPort() {
        let config = ContainerConfig(
            image: "coredns",
            ports: [PortMapping(hostPort: 5353, containerPort: 53, portProtocol: .udp)]
        )

        let args = ContainerEngine.buildRunArguments(name: "dns", config: config)

        let idx = args.firstIndex(of: "-p")
        #expect(idx != nil)
        if let idx { #expect(args[idx + 1] == "5353:53/udp") }
    }

    @Test("Run arguments omit -p when no ports requested")
    func testRunArgumentsNoPorts() {
        let config = ContainerConfig(image: "alpine")
        let args = ContainerEngine.buildRunArguments(name: "bare", config: config)
        #expect(!args.contains("-p"))
    }

    @Test("Container CLI resolver prefers Homebrew installation")
    func testContainerCLIResolverPrefersHomebrew() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mocker-container-cli-\(UUID().uuidString)")
        let homebrewBin = root.appendingPathComponent("opt/homebrew/bin", isDirectory: true)
        let localBin = root.appendingPathComponent("usr/local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: homebrewBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)

        let homebrewContainer = homebrewBin.appendingPathComponent("container")
        let localContainer = localBin.appendingPathComponent("container")
        FileManager.default.createFile(atPath: homebrewContainer.path, contents: Data())
        FileManager.default.createFile(atPath: localContainer.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: homebrewContainer.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: localContainer.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileManager = RootedFileManager(root: root.path)
        let resolved = ContainerEngine.resolveContainerCLI(fileManager: fileManager, environment: [:])

        #expect(resolved == "/opt/homebrew/bin/container")
    }

    @Test("CLIResolver honors MOCKER_CONTAINER_CLI override")
    func testCLIResolverHonorsEnvOverride() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mocker-cli-override-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let custom = tmp.appendingPathComponent("container")
        FileManager.default.createFile(atPath: custom.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: custom.path)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let resolved = CLIResolver.resolve(
            fileManager: .default,
            environment: ["MOCKER_CONTAINER_CLI": custom.path]
        )

        #expect(resolved == custom.path)
    }

    @Test("CLIResolver falls back through PATH before well-known locations")
    func testCLIResolverUsesPATH() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mocker-cli-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let custom = tmp.appendingPathComponent("container")
        FileManager.default.createFile(atPath: custom.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: custom.path)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let resolved = CLIResolver.resolve(
            fileManager: .default,
            environment: ["PATH": tmp.path]
        )

        #expect(resolved == custom.path)
    }

    @Test("CLIResolver falls through to final default when nothing matches")
    func testCLIResolverIgnoresMissingOverride() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mocker-cli-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = RootedFileManager(root: root.path)

        let resolved = CLIResolver.resolve(
            fileManager: fileManager,
            environment: [
                "MOCKER_CONTAINER_CLI": "/nonexistent/path/container",
                "PATH": "",
            ]
        )

        #expect(resolved == "/usr/local/bin/container")
    }

    @Test("CLIResolver prefers PATH over fallback locations")
    func testCLIResolverPathBeatsFallback() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mocker-cli-precedence-\(UUID().uuidString)")
        let pathDir = root.appendingPathComponent("custom/bin", isDirectory: true)
        let homebrewBin = root.appendingPathComponent("opt/homebrew/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: pathDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homebrewBin, withIntermediateDirectories: true)

        for url in [pathDir.appendingPathComponent("container"),
                    homebrewBin.appendingPathComponent("container")] {
            FileManager.default.createFile(atPath: url.path, contents: Data())
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let fileManager = RootedFileManager(root: root.path)
        let resolved = CLIResolver.resolve(
            fileManager: fileManager,
            environment: ["PATH": "/custom/bin"]
        )

        #expect(resolved == "/custom/bin/container")
    }
}

private final class RootedFileManager: FileManager, @unchecked Sendable {
    private let root: String

    init(root: String) {
        self.root = root
        super.init()
    }

    override func isExecutableFile(atPath path: String) -> Bool {
        super.isExecutableFile(atPath: root + path)
    }
}
