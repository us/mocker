import Testing
@testable import MockerKit

/// Tests for `ImageManager.makeBuildArguments` — the pure argument-vector builder
/// behind `mocker build`. Covers the `--builder` wiring added for the exotic-arch
/// remote-builder workaround (apple/container#1496, issue #10).
@Suite("ImageManager build arguments")
struct ImageManagerBuildArgsTests {

    @Test("base arguments are well-formed")
    func baseArgs() {
        let args = ImageManager.makeBuildArguments(
            tag: "myapp:latest", dockerfilePath: "/ctx/Dockerfile", context: "."
        )
        #expect(args.first == "build")
        #expect(args.contains("-t"))
        #expect(args.contains("myapp:latest"))
        #expect(args.contains("-f"))
        #expect(args.contains("/ctx/Dockerfile"))
        // Context is always the trailing positional argument.
        #expect(args.last == ".")
    }

    @Test("--builder is omitted when not provided")
    func builderOmittedByDefault() {
        let args = ImageManager.makeBuildArguments(
            tag: "myapp:latest", dockerfilePath: "/ctx/Dockerfile", context: "."
        )
        #expect(!args.contains("--builder"))
    }

    @Test("--builder is omitted when empty")
    func builderOmittedWhenEmpty() {
        let args = ImageManager.makeBuildArguments(
            tag: "myapp:latest", dockerfilePath: "/ctx/Dockerfile", context: ".", builder: ""
        )
        #expect(!args.contains("--builder"))
    }

    @Test("--builder is forwarded with its value")
    func builderForwarded() {
        let args = ImageManager.makeBuildArguments(
            tag: "myapp:latest", dockerfilePath: "/ctx/Dockerfile", context: ".",
            builder: "remote-ppc64le"
        )
        // The flag and its value must appear adjacently.
        guard let idx = args.firstIndex(of: "--builder") else {
            Issue.record("--builder flag missing from arguments: \(args)")
            return
        }
        #expect(args.indices.contains(idx + 1))
        #expect(args[idx + 1] == "remote-ppc64le")
        // …and the value must not be swallowed by the trailing context positional.
        #expect(args.last == ".")
    }

    @Test("--builder composes with --platform for exotic-arch builds")
    func builderWithExoticPlatform() {
        let args = ImageManager.makeBuildArguments(
            tag: "myapp:latest", dockerfilePath: "/ctx/Dockerfile", context: ".",
            platforms: ["linux/ppc64le"], builder: "remote"
        )
        #expect(args.contains("--platform"))
        #expect(args.contains("linux/ppc64le"))
        #expect(args.contains("--builder"))
        #expect(args.contains("remote"))
    }

    @Test("all optional flags are emitted in the expected shape")
    func fullArgs() {
        let args = ImageManager.makeBuildArguments(
            tag: "myapp:1.0", dockerfilePath: "/ctx/Dockerfile", context: "ctx",
            noCache: true, buildArgs: ["KEY=val"], platforms: ["linux/arm64", "linux/amd64"],
            target: "builder-stage", labels: ["a=b"], quiet: true, progress: "plain",
            output: ["type=docker"], builder: "myremote"
        )
        #expect(args.contains("--no-cache"))
        #expect(adjacent(args, "--build-arg", "KEY=val"))
        #expect(adjacent(args, "--target", "builder-stage"))
        #expect(adjacent(args, "-l", "a=b"))
        #expect(args.contains("-q"))
        #expect(adjacent(args, "--progress", "plain"))
        #expect(adjacent(args, "-o", "type=docker"))
        #expect(adjacent(args, "--builder", "myremote"))
        // Both platforms must be present.
        #expect(args.contains("linux/arm64"))
        #expect(args.contains("linux/amd64"))
        #expect(args.last == "ctx")
    }

    /// Helper: assert `flag` is immediately followed by `value` somewhere in `args`.
    private func adjacent(_ args: [String], _ flag: String, _ value: String) -> Bool {
        for (i, a) in args.enumerated() where a == flag {
            if i + 1 < args.count, args[i + 1] == value { return true }
        }
        return false
    }
}
