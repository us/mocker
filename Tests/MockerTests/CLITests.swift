import Testing
import ArgumentParser
@testable import Mocker

@Suite("CLI Tests")
struct CLITests {
    @Test("Mocker version is defined and consistent")
    func version() {
        let version = Version.currentVersion
        #expect(!version.isEmpty)
        // x-release-please-start-version
        #expect(version == "0.3.1")
        // x-release-please-end
    }

    @Test("Run command accepts --env-file flag")
    func runEnvFileFlag() throws {
        let command = try Run.parse(["--env-file", "test.env", "alpine"])
        #expect(command.envFile == "test.env")
        #expect(command.image == "alpine")
    }

    @Test("Run command accepts nested virtualization flags")
    func runVirtualizationFlags() throws {
        let command = try Run.parse(["--virtualization", "--kernel", "/tmp/vmlinux", "ubuntu:latest"])
        #expect(command.virtualization == true)
        #expect(command.kernel == "/tmp/vmlinux")
        #expect(command.image == "ubuntu:latest")
    }

    @Test("Create command accepts nested virtualization flags")
    func createVirtualizationFlags() throws {
        let command = try Create.parse(["--virtualization", "--kernel", "/tmp/vmlinux", "ubuntu:latest"])
        #expect(command.virtualization == true)
        #expect(command.kernel == "/tmp/vmlinux")
        #expect(command.image == "ubuntu:latest")
    }

    @Test("Pull command accepts --platform flag")
    func pullPlatformFlag() throws {
        let command = try Pull.parse(["--platform", "linux/amd64", "alpine:latest"])
        #expect(command.platform == "linux/amd64")
        #expect(command.image == "alpine:latest")
    }

    @Test("Pull command leaves platform nil when omitted")
    func pullPlatformDefaultsNil() throws {
        let command = try Pull.parse(["alpine:latest"])
        #expect(command.platform == nil)
    }

    @Test("Push command accepts --platform flag")
    func pushPlatformFlag() throws {
        let command = try Push.parse(["--platform", "linux/arm64", "myrepo/app:1.0"])
        #expect(command.platform == "linux/arm64")
        #expect(command.image == "myrepo/app:1.0")
    }

    @Test("Build command accepts repeated --platform flags")
    func buildRepeatedPlatform() throws {
        let command = try Build.parse([
            "-t", "multi:latest",
            "--platform", "linux/amd64",
            "--platform", "linux/arm64",
            ".",
        ])
        #expect(command.platform == ["linux/amd64", "linux/arm64"])
        #expect(command.tag == "multi:latest")
    }

    @Test("Build command leaves platform empty when omitted")
    func buildPlatformDefaultsEmpty() throws {
        let command = try Build.parse(["-t", "x:latest", "."])
        #expect(command.platform.isEmpty)
    }

    @Test("Manifest inspect command parses reference argument")
    func manifestInspectParse() throws {
        let command = try ManifestInspect.parse(["myrepo/multi:latest"])
        #expect(command.manifestList == "myrepo/multi:latest")
    }

    @Test("Manifest create command parses list name and children")
    func manifestCreateParse() throws {
        let command = try ManifestCreate.parse([
            "myrepo/multi:latest",
            "myrepo/app:linux-amd64",
            "myrepo/app:linux-arm64",
        ])
        #expect(command.manifestList == "myrepo/multi:latest")
        #expect(command.manifests == ["myrepo/app:linux-amd64", "myrepo/app:linux-arm64"])
    }

    @Test("Manifest add command parses list and child")
    func manifestAddParse() throws {
        let command = try ManifestAdd.parse(["multi:latest", "child:linux-amd64"])
        #expect(command.manifestList == "multi:latest")
        #expect(command.manifest == "child:linux-amd64")
    }

    @Test("Manifest rm command parses list and target")
    func manifestRmParse() throws {
        let platformCmd = try ManifestRm.parse(["multi:latest", "linux/amd64"])
        #expect(platformCmd.target == "linux/amd64")
        let digestCmd = try ManifestRm.parse(["multi:latest", "sha256:deadbeef"])
        #expect(digestCmd.target == "sha256:deadbeef")
    }

    @Test("Manifest push command parses list name")
    func manifestPushParse() throws {
        let command = try ManifestPush.parse(["myrepo/multi:latest"])
        #expect(command.manifestList == "myrepo/multi:latest")
    }

    @Test("Manifest annotate parses os/arch/variant overrides")
    func manifestAnnotateParse() throws {
        let command = try ManifestAnnotate.parse([
            "multi:latest", "child:arm64",
            "--os", "linux",
            "--arch", "arm64",
            "--variant", "v8",
        ])
        #expect(command.manifestList == "multi:latest")
        #expect(command.manifest == "child:arm64")
        #expect(command.os == "linux")
        #expect(command.arch == "arm64")
        #expect(command.variant == "v8")
    }

    @Test("Manifest annotate leaves overrides nil when omitted")
    func manifestAnnotateDefaults() throws {
        let command = try ManifestAnnotate.parse(["multi:latest", "child:arm64"])
        #expect(command.os == nil)
        #expect(command.arch == nil)
        #expect(command.variant == nil)
    }
}
