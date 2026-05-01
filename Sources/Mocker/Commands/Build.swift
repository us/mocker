import ArgumentParser
import Foundation
import MockerKit

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build an image from a Dockerfile"
    )

    @Argument(help: "Build context path")
    var context: String = "."

    @Option(name: .shortAndLong, help: "Name and optionally a tag (name:tag)")
    var tag: String

    @Option(name: .shortAndLong, help: "Name of the Dockerfile")
    var file: String = "Dockerfile"

    @Flag(name: .long, help: "Do not use cache when building")
    var noCache = false

    @Option(name: .customLong("build-arg"), parsing: .singleValue, help: "Set build-time variables")
    var buildArg: [String] = []

    @Option(name: .long, help: "Set target platform for build")
    var platform: String?

    @Option(name: .long, help: "Set the target build stage to build")
    var target: String?

    @Option(name: .shortAndLong, parsing: .singleValue, help: "Set metadata for an image")
    var label: [String] = []

    @Flag(name: .long, help: "Always attempt to pull a newer version of the image")
    var pull = false

    @Flag(name: .shortAndLong, help: "Suppress the build output and print image ID on success")
    var quiet = false

    @Option(name: .long, help: "Set the networking mode for the RUN instructions during build")
    var network: String?

    // --- Additional Docker/BuildKit-compatible flags ---

    @Option(name: .customLong("add-host"), parsing: .singleValue, help: "Add a custom host-to-IP mapping (host:ip)")
    var addHost: [String] = []

    @Option(name: .long, help: "Allow extra privileged entitlement (e.g., network.host, security.insecure)")
    var allow: String?

    @Option(name: .long, parsing: .singleValue, help: "Add an annotation to the image")
    var annotation: [String] = []

    @Option(name: .long, parsing: .singleValue, help: "Attestation parameters (type=sbom|provenance)")
    var attest: [String] = []

    @Option(name: .customLong("build-context"), parsing: .singleValue, help: "Additional build contexts (e.g., name=path)")
    var buildContext: [String] = []

    @Option(name: .long, help: "Override the configured builder instance")
    var builder: String?

    @Option(name: .customLong("cache-from"), parsing: .singleValue, help: "External cache sources (e.g., type=registry,ref=image)")
    var cacheFrom: [String] = []

    @Option(name: .customLong("cache-to"), parsing: .singleValue, help: "Cache export destinations (e.g., type=registry,ref=image)")
    var cacheTo: [String] = []

    @Option(name: .long, help: "Set method for evaluating build (check, outline, targets)")
    var call: String?

    @Option(name: .customLong("cgroup-parent"), help: "Set the parent cgroup for the RUN instructions during build")
    var cgroupParent: String?

    @Flag(name: .long, help: "Shorthand for --call=check")
    var check = false

    @Flag(name: [.customShort("D"), .long], help: "Enable debug logging")
    var debug = false

    @Option(name: .long, help: "Write the image ID to the file")
    var iidfile: String?

    @Flag(name: .long, help: "Shorthand for --output=type=docker")
    var load = false

    @Option(name: .customLong("metadata-file"), help: "Write build result metadata to the file")
    var metadataFile: String?

    @Option(name: .customLong("no-cache-filter"), parsing: .singleValue, help: "Do not cache specified stages")
    var noCacheFilter: [String] = []

    @Option(name: [.customShort("o"), .long], parsing: .singleValue, help: "Output destination (format: type=local,dest=path)")
    var output: [String] = []

    @Option(name: .long, help: "Set policy for build")
    var policy: String?

    @Option(name: .long, help: "Set type of progress output (auto, plain, tty, rawjson)")
    var progress: String?

    @Option(name: .long, help: "Shorthand for --attest=type=provenance")
    var provenance: String?

    @Flag(name: .long, help: "Shorthand for --output=type=registry")
    var push = false

    @Option(name: .long, help: "Shorthand for --attest=type=sbom")
    var sbom: String?

    @Option(name: .long, parsing: .singleValue, help: "Secret to expose to the build (e.g., id=mysecret,src=/path)")
    var secret: [String] = []

    @Option(name: .customLong("shm-size"), help: "Size of /dev/shm")
    var shmSize: String?

    @Option(name: .long, parsing: .singleValue, help: "SSH agent socket or keys to expose to the build")
    var ssh: [String] = []

    @Option(name: .long, parsing: .singleValue, help: "Ulimit options")
    var ulimit: [String] = []

    func run() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()

        // Multi-arch build: comma-separated platforms
        if let platformStr = platform, platformStr.contains(",") {
            let platforms = platformStr.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            try await runMultiArchBuild(platforms: platforms)
            return
        }

        let manager = try ImageManager(config: config)
        if !quiet {
            print("Building \(tag)...")
        }
        let image = try await manager.build(
            tag: tag, context: context, dockerfile: file, noCache: noCache,
            buildArgs: buildArg, platform: platform, target: target,
            labels: label, quiet: quiet, progress: progress, output: output
        )
        if quiet {
            print(image.shortID)
        } else {
            print("Successfully built \(image.shortID)")
            print("Successfully tagged \(tag)")
        }
    }

    // MARK: - Multi-arch build via Podman

    private func runMultiArchBuild(platforms: [String]) async throws {
        let nativePlatforms: Set<String> = ["linux/arm64", "linux/arm64/v8", "linux/amd64", "linux/x86_64"]
        let exoticPlatforms = platforms.filter { !nativePlatforms.contains($0) }

        print("Multi-arch build: \(platforms.joined(separator: ", "))")
        if !exoticPlatforms.isEmpty {
            print("Note: Exotic arches (\(exoticPlatforms.joined(separator: ", "))) require QEMU via Podman machine.")
        }
        print("Using Podman for all architectures to enable manifest assembly.\n")

        guard await checkPodmanMachineRunning() else {
            var hint = "No running Podman machine found. Start one with:\n"
            hint += "  podman machine start\n\n"
            let native = platforms.filter { nativePlatforms.contains($0) }
            if !native.isEmpty {
                hint += "You can build native arches individually without Podman:\n"
                for arch in native {
                    hint += "  mocker build --platform \(arch) -t \(tag) \(context)\n"
                }
            }
            FileHandle.standardError.write(Data(hint.utf8))
            throw MockerError.buildError("Multi-arch build requires a running Podman machine with QEMU support")
        }

        let baseTag = tag.contains(":") ? tag : "\(tag):latest"
        let colonIdx = baseTag.firstIndex(of: ":")!
        let imageName = String(baseTag[baseTag.startIndex..<colonIdx])
        let imageVersion = String(baseTag[baseTag.index(after: colonIdx)...])

        var archTags: [String] = []
        for arch in platforms {
            let slug = platformSlug(arch)
            let archTag = "\(imageName):\(imageVersion)-\(slug)"
            archTags.append(archTag)
            print("Building [\(arch)] → \(archTag)")
            try await runPodmanBuild(platform: arch, tag: archTag)
            print("")
        }

        print("Assembling manifest: \(tag)")
        try await runPodmanManifestCreate(manifestTag: tag, imageTags: archTags)

        print("\nSuccessfully built multi-arch image: \(tag)")
        print("Platforms: \(platforms.joined(separator: ", "))")
        print("Arch-specific images:")
        for (arch, archTag) in zip(platforms, archTags) {
            print("  \(arch) → \(archTag)")
        }
    }

    private func checkPodmanMachineRunning() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["podman", "machine", "list", "--format", "{{.Running}}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return false }
        let exitCode = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
        }
        guard exitCode == 0 else { return false }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.contains("true")
    }

    private func runPodmanBuild(platform: String, tag: String) async throws {
        let contextURL = context.hasPrefix("/")
            ? URL(fileURLWithPath: context)
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(context).standardized
        let dockerfilePath = contextURL.appendingPathComponent(file).path

        var args = ["build", "--platform", platform, "-t", tag, "-f", dockerfilePath]
        if noCache { args.append("--no-cache") }
        for arg in buildArg { args += ["--build-arg", arg] }
        if let t = target { args += ["--target", t] }
        for l in label { args += ["-l", l] }
        args.append(contextURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["podman"] + args
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        let exitCode = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
        }
        guard exitCode == 0 else {
            throw MockerError.buildError("podman build failed for \(platform) (exit \(exitCode))")
        }
    }

    private func runPodmanManifestCreate(manifestTag: String, imageTags: [String]) async throws {
        // Remove existing manifest first (ignore errors)
        let rmProcess = Process()
        rmProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        rmProcess.arguments = ["podman", "manifest", "rm", manifestTag]
        rmProcess.standardOutput = Pipe()
        rmProcess.standardError = Pipe()
        try? rmProcess.run()
        rmProcess.waitUntilExit()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["podman", "manifest", "create", manifestTag] + imageTags
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        let exitCode = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
        }
        guard exitCode == 0 else {
            throw MockerError.buildError("podman manifest create failed (exit \(exitCode))")
        }
    }

    private func platformSlug(_ platform: String) -> String {
        // linux/arm64/v8 → arm64v8, linux/ppc64le → ppc64le
        let parts = platform.split(separator: "/").dropFirst()
        return parts.joined()
    }
}

