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

@Suite("ImageManager Compose dockerfile path resolver")
struct ImageManagerComposeDockerfilePathTests {

    // Regression: context=./app, cwd=/project, dockerfile=default → must be /project/app/Dockerfile, NOT /project/Dockerfile
    @Test("default dockerfile resolves relative to context, not CWD (regression guard)")
    func composeDefaultDockerfileResolvesRelativeToContext() {
        let result = ImageManager.composeDockerfilePath(
            context: "./app",
            dockerfile: "Dockerfile",
            cwd: "/project"
        )
        #expect(result == "/project/app/Dockerfile")
        #expect(result != "/project/Dockerfile")
    }

    // relative dockerfile resolves relative to context, not CWD
    @Test("relative dockerfile resolves relative to context")
    func composeRelativeDockerfileResolvesRelativeToContext() {
        let result = ImageManager.composeDockerfilePath(
            context: "./app",
            dockerfile: "Dockerfile.prod",
            cwd: "/project"
        )
        #expect(result == "/project/app/Dockerfile.prod")
    }

    // absolute dockerfile is returned verbatim regardless of context
    @Test("absolute dockerfile is returned verbatim")
    func composeAbsoluteDockerfileVerbatim() {
        let result = ImageManager.composeDockerfilePath(
            context: "./app",
            dockerfile: "/custom/path/Dockerfile",
            cwd: "/project"
        )
        #expect(result == "/custom/path/Dockerfile")
    }

    // context already absolute — still resolves dockerfile relative to it
    @Test("absolute context with relative dockerfile resolves correctly")
    func composeAbsoluteContextRelativeDockerfile() {
        let result = ImageManager.composeDockerfilePath(
            context: "/project/app",
            dockerfile: "Dockerfile.dev",
            cwd: "/project"
        )
        #expect(result == "/project/app/Dockerfile.dev")
    }

    // context == CWD — common case, must also be correct
    @Test("when context equals CWD relative dockerfile resolves to context/dockerfile")
    func composeContextEqualsCWD() {
        let result = ImageManager.composeDockerfilePath(
            context: ".",
            dockerfile: "Dockerfile",
            cwd: "/project"
        )
        #expect(result == "/project/Dockerfile")
    }
}

@Suite("ImageManager Dockerfile path resolver")
struct ImageManagerDockerfileResolverTests {

    // Scenario 1 (spec): absolute -f is used verbatim — devcontainer regression case
    @Test("absolute -f path is returned verbatim")
    func resolveAbsoluteUsedVerbatim() {
        let result = ImageManager.resolveDockerfilePath(
            context: "/var/work/build-1234",
            dockerfile: "/var/work/build-1234/Dockerfile.buildContent",
            cwd: "/some/unrelated/cwd"
        )
        #expect(result == "/var/work/build-1234/Dockerfile.buildContent")
    }

    // Scenario 1 negative assertion: absolute -f must NOT be doubled onto context
    @Test("absolute -f is not concatenated onto context")
    func resolveAbsoluteNotDoubled() {
        let result = ImageManager.resolveDockerfilePath(
            context: "/var/work/build-1234",
            dockerfile: "/var/work/build-1234/Dockerfile.buildContent",
            cwd: "/some/unrelated/cwd"
        )
        #expect(!result.contains("/var/work/build-1234/var/work/build-1234"))
    }

    // Scenario 3 (spec): relative -f resolved against CWD, not context
    @Test("relative -f resolves against CWD when CWD differs from context")
    func resolveRelativeCWDNotContext() {
        let result = ImageManager.resolveDockerfilePath(
            context: "/srv/builds/ctx",
            dockerfile: "dockerfiles/Dockerfile.prod",
            cwd: "/home/user/project"
        )
        #expect(result == "/home/user/project/dockerfiles/Dockerfile.prod")
    }

    // Scenario 4 (spec): relative -f where CWD equals context — no regression for common case
    @Test("relative -f where CWD equals context produces same result as before")
    func resolveRelativeCWDEqualsContext() {
        let result = ImageManager.resolveDockerfilePath(
            context: "/home/user/myapp",
            dockerfile: "Dockerfile.dev",
            cwd: "/home/user/myapp"
        )
        #expect(result == "/home/user/myapp/Dockerfile.dev")
    }

    // Scenario 5 (spec): nil -f uses context root
    @Test("nil dockerfile resolves to context/Dockerfile")
    func resolveNilUsesContextRoot() {
        let result = ImageManager.resolveDockerfilePath(
            context: "/srv/builds/ctx",
            dockerfile: nil,
            cwd: "/some/cwd"
        )
        #expect(result == "/srv/builds/ctx/Dockerfile")
    }

    // Scenario 6 (spec): missing abs path — resolver returns correct non-doubled string
    @Test("missing absolute path resolves to the verbatim path string")
    func resolveMissingAbsolutePathString() {
        let result = ImageManager.resolveDockerfilePath(
            context: "/any/context",
            dockerfile: "/nonexistent/path/Dockerfile",
            cwd: "/any/cwd"
        )
        #expect(result == "/nonexistent/path/Dockerfile")
        #expect(!result.contains("/any/context/nonexistent"))
    }

    // Scenario 7 (spec): missing default path — nil + context → context/Dockerfile, not doubled
    @Test("missing default dockerfile resolves to context/Dockerfile without doubling")
    func resolveMissingDefaultPathString() {
        let result = ImageManager.resolveDockerfilePath(
            context: "/some/context",
            dockerfile: nil,
            cwd: "/any/cwd"
        )
        #expect(result == "/some/context/Dockerfile")
        #expect(!result.contains("/some/context/some/context"))
    }
}
