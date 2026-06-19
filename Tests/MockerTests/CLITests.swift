import Foundation
import Testing
import ArgumentParser
import MockerKit
@testable import Mocker

@Suite("CLI Tests")
struct CLITests {
    @Test("Mocker version is defined and consistent")
    func version() {
        let version = Version.currentVersion
        #expect(!version.isEmpty)
        // x-release-please-start-version
        #expect(version == "0.4.1")
        // x-release-please-end
    }

    @Test("Run command accepts --env-file flag")
    func runEnvFileFlag() throws {
        let command = try Run.parse(["--env-file", "test.env", "alpine"])
        #expect(command.envFile == "test.env")
        #expect(command.image == "alpine")
    }

    @Test("Compose subcommand accepts repeated -f flags")
    func composeRepeatedFile() throws {
        let command = try ComposePull.parse(["-f", "a.yaml", "-f", "b.yaml"])
        #expect(command.options.files == ["a.yaml", "b.yaml"])
    }

    @Test("Compose up parses -f together with a subcommand flag")
    func composeUpFileAndFlag() throws {
        let command = try ComposeUp.parse(["-f", "docker-compose.yml", "--detach"])
        #expect(command.options.files == ["docker-compose.yml"])
        #expect(command.detach == true)
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

    @Test("image ls command accepts all list flags")
    func imageLsAllFlags() throws {
        let command = try ImageLs.parse(["--quiet", "--all", "--filter", "reference=nginx", "--format", "{{.ID}}", "--digests", "--no-trunc", "--tree"])
        #expect(command.options.quiet == true)
        #expect(command.options.all == true)
        #expect(command.options.filter == ["reference=nginx"])
        #expect(command.options.format == "{{.ID}}")
        #expect(command.options.digests == true)
        #expect(command.options.noTrunc == true)
        #expect(command.options.tree == true)
    }

    @Test("image ls --filter narrows by reference and label")
    func imageLsFilter() throws {
        let images = [
            ImageInfo(id: "a", repository: "nginx", tag: "latest", labels: ["env": "prod"]),
            ImageInfo(id: "b", repository: "redis", tag: "7", labels: ["env": "dev"]),
        ]
        let byRef = try ImageLs.parse(["--filter", "reference=nginx"]).options
        #expect(byRef.filtered(images).map(\.id) == ["a"])

        let byLabel = try ImageLs.parse(["--filter", "label=env=dev"]).options
        #expect(byLabel.filtered(images).map(\.id) == ["b"])
    }

    @Test("image ls --format substitutes repository, tag and labels")
    func imageLsFormat() throws {
        let img = ImageInfo(id: "abc123def456789", repository: "nginx", tag: "latest", labels: ["env": "prod"])
        let opts = try ImageLs.parse(["--format", "{{.Repository}}:{{.Tag}} {{.Labels}}"]).options
        #expect(opts.formatLine(img) == "nginx:latest env=prod")

        let noTrunc = try ImageLs.parse(["--format", "{{.ID}}", "--no-trunc"]).options
        #expect(noTrunc.formatLine(img) == "abc123def456789")
    }

    @Test("container ls command accepts all list flags")
    func containerLsAllFlags() throws {
        let command = try ContainerLs.parse(["--all", "--quiet", "--filter", "status=running", "--format", "{{.ID}}", "--no-trunc", "-n", "3", "--latest", "--size"])
        #expect(command.options.all == true)
        #expect(command.options.quiet == true)
        #expect(command.options.filter == ["status=running"])
        #expect(command.options.format == "{{.ID}}")
        #expect(command.options.noTrunc == true)
        #expect(command.options.last == 3)
        #expect(command.options.latest == true)
        #expect(command.options.size == true)
    }

    @Test("container ls --filter narrows by status and name")
    func containerLsFilter() throws {
        let containers = [
            ContainerInfo(id: "a", name: "web", image: "nginx", state: .running, status: "Up", created: .distantPast),
            ContainerInfo(id: "b", name: "db", image: "redis", state: .exited, status: "Exited", created: .distantPast),
        ]
        let byStatus = try ContainerLs.parse(["--filter", "status=running"]).options
        #expect(byStatus.filtered(containers).map(\.id) == ["a"])

        let byName = try ContainerLs.parse(["--filter", "name=db"]).options
        #expect(byName.filtered(containers).map(\.id) == ["b"])
    }
}
