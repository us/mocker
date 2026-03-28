import ArgumentParser
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
}
