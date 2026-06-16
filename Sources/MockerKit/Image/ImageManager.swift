import Foundation
import Containerization
import ContainerizationOCI

/// Manages container images using Apple's Containerization framework.
public actor ImageManager {
    private let imageStore: Containerization.ImageStore

    public init(config: MockerConfig = MockerConfig()) throws {
        self.imageStore = try Containerization.ImageStore(path: config.ociStorePath)
    }

    // MARK: - Pull

    /// Pull an image from a registry.
    /// Returns (image, alreadyExisted) so the CLI can show the right status message.
    /// - Parameter platform: optional `linux/amd64`-style filter; nil pulls the full manifest list.
    public func pull(_ reference: String, platform: String? = nil) async throws -> (ImageInfo, Bool) {
        let normalized = try Self.normalize(reference)
        let parsedPlatform = try platform.map { try ContainerizationOCI.Platform(from: $0) }

        // Only short-circuit when the caller did not request a specific platform —
        // a platform-filtered pull may need to fetch additional descriptors that
        // the existing entry does not cover.
        if parsedPlatform == nil,
           let existing = try? await imageStore.get(reference: normalized) {
            return (Self.toImageInfo(existing), true)
        }

        let image = try await imageStore.pull(reference: normalized, platform: parsedPlatform)
        return (Self.toImageInfo(image), false)
    }

    // MARK: - List

    /// List all local images — merges Apple CLI store with our OCI store.
    public func list() async throws -> [ImageInfo] {
        // Primary: Apple CLI store (includes pulled and built images)
        let cliImages = try await listFromCLI()
        if !cliImages.isEmpty { return cliImages }

        // Fallback: our OCI store
        let images = try await imageStore.list()
        return images.map(Self.toImageInfo)
    }

    private func listFromCLI() async throws -> [ImageInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.containerCLI)
        process.arguments = ["images", "ls"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        let output = await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }

        return parseCLIImageList(output)
    }

    private func parseCLIImageList(_ output: String) -> [ImageInfo] {
        var results: [ImageInfo] = []
        let lines = output.components(separatedBy: "\n").dropFirst() // skip header
        for line in lines {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 3 else { continue }
            let name = cols[0]
            let tag = cols[1]
            let digest = "sha256:" + cols[2]
            let repo = name.contains(".") || name.contains("/") ? name : "docker.io/library/\(name)"
            results.append(ImageInfo(id: digest, repository: repo, tag: tag, size: 0, created: Date()))
        }
        return results
    }

    // MARK: - Remove

    /// Remove an image by reference.
    public func remove(_ reference: String) async throws -> ImageInfo {
        let normalized = try Self.normalize(reference)
        guard let image = try? await imageStore.get(reference: normalized) else {
            throw MockerError.imageNotFound(reference)
        }
        let info = Self.toImageInfo(image)
        try await imageStore.delete(reference: normalized)
        return info
    }

    // MARK: - Tag

    /// Tag an image with a new reference.
    public func tag(_ source: String, _ target: String) async throws {
        let src = try Self.normalize(source)
        let dst = try Self.normalize(target)
        _ = try await imageStore.tag(existing: src, new: dst)
    }

    // MARK: - Inspect

    /// Inspect an image reference, returning a Docker-compatible ImageInspect.
    public func inspect(_ reference: String, platform: String? = nil) async throws -> ImageInspect {
        let normalized = try Self.normalize(reference)
        guard let image = try? await imageStore.get(reference: normalized) else {
            throw MockerError.imageNotFound(reference)
        }
        let resolvedPlatform: ContainerizationOCI.Platform
        if let platformString = platform {
            resolvedPlatform = try ContainerizationOCI.Platform(from: platformString)
        } else {
            resolvedPlatform = ContainerizationOCI.Platform.current
        }

        let manifest: ContainerizationOCI.Manifest
        let config: ContainerizationOCI.Image
        let configExtras: ImageInspectConfigExtras
        if let matched = try? await image.manifest(for: resolvedPlatform) {
            manifest = matched
            let configContent = try await image.getContent(digest: matched.config.digest)
            config = try configContent.decode()
            configExtras = try decodeImageInspectConfigExtras(from: configContent.data())
        } else {
            // No exact platform match: a single-arch or sole-manifest image is still
            // inspectable — Docker returns its only manifest. Multi-manifest indexes
            // with no match remain a genuine error.
            let index = try await image.index()
            guard let sole = Self.soleManifestDescriptor(from: index.manifests) else {
                throw MockerError.operationFailed(
                    "platform \(resolvedPlatform.description) not available for image \(reference)")
            }
            manifest = try await image.getContent(digest: sole.digest).decode()
            let configContent = try await image.getContent(digest: manifest.config.digest)
            config = try configContent.decode()
            configExtras = try decodeImageInspectConfigExtras(from: configContent.data())
        }
        let repoMetadata = await repoMetadata(for: image, fallbackReference: normalized)
        return mapToImageInspect(
            config: config,
            manifest: manifest,
            reference: normalized,
            indexDigest: image.digest,
            configExtras: configExtras,
            repoTags: repoMetadata.tags,
            repoDigests: repoMetadata.digests
        )
    }

    private func repoMetadata(
        for image: Containerization.Image,
        fallbackReference: String
    ) async -> (tags: [String], digests: [String]) {
        let images = (try? await imageStore.list()) ?? [image]
        return Self.repoMetadata(for: image, localImages: images, fallbackReference: fallbackReference)
    }

    static func repoMetadata(
        for image: Containerization.Image,
        localImages images: [Containerization.Image],
        fallbackReference: String
    ) -> (tags: [String], digests: [String]) {
        let matchingReferences = images
            .filter { $0.digest == image.digest }
            .map(\.reference)
            .sorted()
        let references = matchingReferences.isEmpty ? [image.reference, fallbackReference] : matchingReferences

        let tags = Set(references.compactMap(Self.repoTag(from:))).sorted()
        // Containerization exposes local references and the image's root descriptor digest,
        // but not a registry-provided list of repo digest aliases. Report only repos found
        // in local references that point at this exact stored descriptor.
        let digests = Set(references.map { "\(Self.repositoryName(from: $0))@\(image.digest)" })
            .sorted()

        return (tags, digests)
    }

    private static func referenceHasTag(_ reference: String) -> Bool {
        let beforeDigest = reference.split(separator: "@", maxSplits: 1).first.map(String.init) ?? reference
        let lastComponent = beforeDigest
            .split(separator: "/", omittingEmptySubsequences: false)
            .last
            .map(String.init) ?? beforeDigest
        return lastComponent.contains(":")
    }

    private static func repoTag(from reference: String) -> String? {
        let beforeDigest = reference.split(separator: "@", maxSplits: 1).first.map(String.init) ?? reference
        return referenceHasTag(beforeDigest) ? beforeDigest : nil
    }

    private static func repositoryName(from reference: String) -> String {
        let withoutDigest = reference.split(separator: "@", maxSplits: 1).first.map(String.init) ?? reference
        var parts = withoutDigest.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if var last = parts.last, let colonIndex = last.lastIndex(of: ":") {
            last = String(last[last.startIndex..<colonIndex])
            parts[parts.count - 1] = last
        }
        return parts.joined(separator: "/")
    }

    /// Returns the only manifest descriptor when an index has exactly one, enabling
    /// single-arch images to be inspected even if their platform differs from the
    /// requested one. Returns nil for empty or multi-manifest indexes.
    static func soleManifestDescriptor(
        from manifests: [ContainerizationOCI.Descriptor]
    ) -> ContainerizationOCI.Descriptor? {
        manifests.count == 1 ? manifests.first : nil
    }

    // MARK: - Build

    private static let containerCLI = CLIResolver.resolve()

    /// Construct the argument vector for `container build`.
    ///
    /// Pure and side-effect-free so it can be unit-tested without spawning a
    /// process. The `builder` value maps to `container build --builder`, the
    /// manual escape hatch for exotic architectures (ppc64le/s390x/riscv64) that
    /// the local arm64 BuildKit VM cannot emulate — see README and apple/container#1496.
    static func makeBuildArguments(
        tag: String, dockerfilePath: String, context: String, noCache: Bool = false,
        buildArgs: [String] = [], platforms: [String] = [], target: String? = nil,
        labels: [String] = [], quiet: Bool = false, progress: String? = nil,
        output: [String] = [], builder: String? = nil
    ) -> [String] {
        var args = ["build", "-t", tag, "-f", dockerfilePath]
        if noCache { args.append("--no-cache") }
        for arg in buildArgs { args += ["--build-arg", arg] }
        for p in platforms { args += ["--platform", p] }
        if let target { args += ["--target", target] }
        for l in labels { args += ["-l", l] }
        if quiet { args.append("-q") }
        if let progress { args += ["--progress", progress] }
        for o in output { args += ["-o", o] }
        if let builder, !builder.isEmpty { args += ["--builder", builder] }
        args.append(context)
        return args
    }

    /// Build an image from a Dockerfile using the `container` CLI.
    /// - Parameter platforms: pass multiple values to build a multi-arch manifest list (e.g. `["linux/amd64", "linux/arm64"]`).
    /// - Parameter builder: optional named builder instance forwarded to `container build --builder`,
    ///   enabling a remote BuildKit node for exotic architectures (apple/container#1496).
    public func build(tag: String, context: String, dockerfile: String = "Dockerfile", noCache: Bool = false, buildArgs: [String] = [], platforms: [String] = [], target: String? = nil, labels: [String] = [], quiet: Bool = false, progress: String? = nil, output: [String] = [], builder: String? = nil) async throws -> ImageInfo {
        let contextURL: URL
        if context.hasPrefix("/") {
            contextURL = URL(fileURLWithPath: context)
        } else {
            contextURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(context)
                .standardized
        }
        let dockerfilePath = contextURL.appendingPathComponent(dockerfile).path

        guard FileManager.default.fileExists(atPath: dockerfilePath) else {
            throw MockerError.buildError("Dockerfile not found at \(dockerfilePath)")
        }

        let args = Self.makeBuildArguments(
            tag: tag, dockerfilePath: dockerfilePath, context: context, noCache: noCache,
            buildArgs: buildArgs, platforms: platforms, target: target, labels: labels,
            quiet: quiet, progress: progress, output: output, builder: builder
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.containerCLI)
        process.arguments = args
        // Inherit terminal I/O so build progress is shown live
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()

        let exitCode = await withCheckedContinuation { continuation in
            process.terminationHandler = { p in
                continuation.resume(returning: p.terminationStatus)
            }
        }

        guard exitCode == 0 else {
            throw MockerError.buildError("Build failed with exit code \(exitCode)")
        }

        // Fetch real image info from the store after build
        let normalized = try Self.normalize(tag)
        if let image = try? await imageStore.get(reference: normalized) {
            return Self.toImageInfo(image)
        }

        // Fallback if store lookup fails (image was built but not indexed)
        let ref = try ImageReference.parse(tag)
        let digest = "sha256:" + (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        return ImageInfo(id: digest, repository: ref.fullRepository, tag: ref.tag, size: 0, created: Date())
    }

    // MARK: - Push

    /// Push an image to a registry.
    /// - Parameter platform: optional `linux/amd64`-style filter; nil pushes the full manifest list.
    public func push(_ reference: String, platform: String? = nil) async throws {
        let normalized = try Self.normalize(reference)
        guard (try? await imageStore.get(reference: normalized)) != nil else {
            throw MockerError.imageNotFound(reference)
        }
        let parsedPlatform = try platform.map { try ContainerizationOCI.Platform(from: $0) }
        try await imageStore.push(reference: normalized, platform: parsedPlatform)
    }

    // MARK: - Save / Load

    /// Save images to an OCI tar archive.
    public func save(references: [String], to outputPath: String) async throws {
        let normalizedRefs = try references.map { try Self.normalize($0) }
        let outputURL = URL(fileURLWithPath: outputPath)
        try await imageStore.save(references: normalizedRefs, out: outputURL)
    }

    /// Load images from an OCI tar archive.
    public func load(from inputPath: String) async throws -> [ImageInfo] {
        let inputURL = URL(fileURLWithPath: inputPath)
        let images = try await imageStore.load(from: inputURL)
        return images.map(Self.toImageInfo)
    }

    // MARK: - Helpers

    private static func normalize(_ reference: String) throws -> String {
        // ContainerizationOCI.Reference.parse requires a fully-qualified reference with domain.
        // Docker-style short references ("alpine", "nginx:1.25", "user/image:tag") need a domain.
        var fullRef = reference
        let parts = reference.split(separator: "/", maxSplits: 1)
        if parts.count == 1 {
            // No slash → single name like "alpine:latest"
            fullRef = "docker.io/library/\(reference)"
        } else {
            let domain = String(parts[0])
            // Domain must contain a dot, colon, or be "localhost"
            let looksLikeDomain = domain.contains(".") || domain.contains(":") || domain == "localhost"
            if !looksLikeDomain {
                // e.g. "myuser/myimage:tag" — no domain, add docker.io
                fullRef = "docker.io/\(reference)"
            }
        }
        let ref = try ContainerizationOCI.Reference.parse(fullRef)
        ref.normalize()
        return ref.description
    }

    private static func toImageInfo(_ image: Containerization.Image) -> ImageInfo {
        // Parse repo and tag from the reference string
        let ref = try? ImageReference.parse(image.reference)
        let repository = ref?.fullRepository ?? image.reference
        let tag = ref?.tag ?? "latest"

        return ImageInfo(
            id: image.digest,
            repository: repository,
            tag: tag,
            size: 0,         // Size requires reading all layer blobs — expensive
            created: Date()  // Created requires reading image config — async
        )
    }
}
