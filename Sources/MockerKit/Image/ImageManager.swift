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
            return (await Self.toImageInfo(existing), true)
        }
        // A local image ID (compose `image: d9e853e87e55`) is that image; as a name it
        // would be pulled as `docker.io/library/d9e853e87e55:latest`.
        if parsedPlatform == nil, let name = try await name(forID: reference),
           let existing = try? await imageStore.get(reference: name) {
            return (await Self.toImageInfo(existing), true)
        }

        let image = try await imageStore.pull(
            reference: normalized, platform: parsedPlatform, auth: RegistryAuth.resolve(for: normalized)
        )
        return (await Self.toImageInfo(image), false)
    }

    // MARK: - List

    /// List all local images — merges Apple CLI store with our OCI store.
    /// - Parameter enrich: resolve each image's real SIZE/CREATED. Costs a manifest and
    ///   config read per image, so callers that only compare repository and tag pass false.
    public func list(enrich: Bool = true) async throws -> [ImageInfo] {
        // Primary: Apple CLI store (includes pulled and built images)
        let cliImages = try await listFromCLI(enrich: enrich)
        if !cliImages.isEmpty { return cliImages }

        // Fallback: our OCI store
        let images = try await imageStore.list()
        var infos: [ImageInfo] = []
        for image in images {
            infos.append(enrich ? await Self.toImageInfo(image) : Self.basicImageInfo(image))
        }
        return infos
    }

    private func listFromCLI(enrich: Bool) async throws -> [ImageInfo] {
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

        let parsed = parseCLIImageList(output)
        return enrich ? await self.enrich(parsed) : parsed.map(\.info)
    }

    /// Fill in SIZE and CREATED for a CLI-derived listing.
    ///
    /// `container images ls` prints only NAME/TAG/DIGEST, so the values come from each
    /// image's manifest and config in the shared content store. An image missing from
    /// the store keeps its unknown (nil) values rather than a fabricated zero.
    private func enrich(_ images: [(info: ImageInfo, reference: String)]) async -> [ImageInfo] {
        var result: [ImageInfo] = []
        result.reserveCapacity(images.count)
        for (info, reference) in images {
            let listedDigest = info.id.replacingOccurrences(of: ".", with: "")
            guard let image = try? await resolve(reference),
                  image.digest.hasPrefix(listedDigest) || listedDigest.hasPrefix(image.digest) else {
                // No match, or a different image happens to answer to that reference —
                // leave the values unknown rather than attaching another image's metadata.
                result.append(info)
                continue
            }
            var enriched = info
            let metadata = await Self.sizeAndCreated(of: image)
            enriched.size = metadata.size
            enriched.created = metadata.created
            result.append(enriched)
        }
        return result
    }

    /// Rows of the CLI listing, each with the reference exactly as the CLI printed it —
    /// a locally built image is stored under that bare reference, not the display form.
    private func parseCLIImageList(_ output: String) -> [(info: ImageInfo, reference: String)] {
        var results: [(info: ImageInfo, reference: String)] = []
        let lines = output.components(separatedBy: "\n").dropFirst() // skip header
        for line in lines {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 3 else { continue }
            let name = cols[0]
            let tag = cols[1]
            let digest = "sha256:" + cols[2]
            let repo = name.contains(".") || name.contains("/") ? name : "docker.io/library/\(name)"
            results.append((ImageInfo(id: digest, repository: repo, tag: tag), "\(name):\(tag)"))
        }
        return results
    }

    // MARK: - Remove

    /// Remove an image by name or ID. A name untags that one reference, as Docker does.
    /// An ID names the image itself: with several tags it is refused unless `force`d, and
    /// forced it untags them all — Docker's rule, and what `images -q | xargs rmi` relies on.
    /// - Returns: each reference untagged, and whether the image is now gone — which is
    ///   when Docker prints `Deleted:`.
    public func remove(_ reference: String, force: Bool = false) async throws -> (untagged: [ImageInfo], deleted: Bool) {
        let image = try await resolve(reference)
        // A hex name that answered as a name is a name; only a digest match is "by ID".
        let byID = Self.looksLikeDigest(reference)
            && !Self.resolutionCandidates(reference).contains(image.reference)
        var images = [image]
        if byID {
            images = try await imageStore.list().filter { $0.digest == image.digest }
            try Self.checkRemovable(byID: image.digest, tags: images.map(\.reference), force: force)
        }
        var untagged: [ImageInfo] = []
        for each in images {
            untagged.append(await Self.toImageInfo(each))
            // Delete the reference that actually matched, never a re-derived one.
            try await imageStore.delete(reference: each.reference)
        }
        let remains = try await imageStore.list().contains { $0.digest == image.digest }
        return (untagged, !remains)
    }

    /// Docker refuses `rmi <id>` while several tags share the image, unless forced; a guess
    /// at which tag was meant would untag the wrong one and still report success. Pure, so
    /// the rule can be tested without a store.
    static func checkRemovable(byID digest: String, tags: [String], force: Bool) throws {
        guard tags.count > 1, !force else { return }
        let shortID = String(digestBody(digest).prefix(12))
        throw MockerError.operationFailed(
            "conflict: unable to delete \(shortID) (must be forced) - image is referenced in multiple repositories")
    }

    // MARK: - Prune

    /// Images the runtime itself depends on; never the user's to prune.
    static let runtimeImagePrefixes = ["ghcr.io/apple/containerization/", "ghcr.io/apple/container-builder-shim/"]

    /// Docker's "dangling" is an image with no name. The store names every image, and an
    /// untagged `mocker build` gets a UUID, so that is what dangling looks like here.
    public static func isDangling(_ image: ImageInfo) -> Bool {
        var name = image.repository
        if name.hasPrefix("docker.io/library/") { name.removeFirst("docker.io/library/".count) }
        return image.tag == "latest" && UUID(uuidString: name) != nil
    }

    /// What `prune` removes: dangling images, or with `all` every image no container uses.
    /// Pure, so the selection can be tested without a store.
    /// - Parameter inUse: image references the way containers spell them (name, name:tag or ID).
    static func pruneCandidates(_ images: [ImageInfo], all: Bool, inUse: [String]) -> [ImageInfo] {
        images.filter { image in
            if runtimeImagePrefixes.contains(where: { image.repository.hasPrefix($0) }) { return false }
            // A container keeps its image in both modes, an untagged build included.
            if inUse.contains(where: { matches(image, reference: $0) }) { return false }
            return all || isDangling(image)
        }
    }

    /// Whether `reference` — `alpine`, `alpine:3.20`, `docker.io/library/alpine:3.20` or an
    /// ID prefix — names `image`.
    static func matches(_ image: ImageInfo, reference: String) -> Bool {
        if looksLikeDigest(reference), digestBody(image.id).hasPrefix(digestBody(reference)) { return true }
        guard let ref = try? ImageReference.parse(reference) else { return false }
        return image.tag == ref.tag
            && (image.repository == ref.fullRepository || image.repository.hasSuffix("/\(ref.repository)"))
    }

    /// Whether a container started from `containerImage` runs the image `reference` names —
    /// `ps --filter ancestor=`. Both sides are looked up in `images` and compared by digest,
    /// so an ID, `alpine:3.20` and `docker.io/library/alpine:3.20` all mean the same image
    /// and a bare `alpine` means `alpine:latest`, as in Docker. An ID prefix shared by two
    /// images names neither. Pure, so the matching can be tested without a store.
    public static func isAncestor(_ reference: String, of containerImage: String, in images: [ImageInfo]) -> Bool {
        let wanted = imageID(reference, in: images), actual = imageID(containerImage, in: images)
        // An image deleted since the container started is only found by the name it ran.
        guard let wanted, let actual else { return containerImage == reference }
        return actual == wanted
    }

    /// ID of the one image `reference` names, looked up like `resolve` does: as a name
    /// first (as typed, with `:latest`, registry-qualified), so `nginx` never means
    /// `bitnami/nginx`, then as an ID prefix, which must name a single image.
    static func imageID(_ reference: String, in images: [ImageInfo]) -> String? {
        let names = resolutionCandidates(reference)
        if let image = images.first(where: { names.contains($0.reference) }) { return image.id }
        guard looksLikeDigest(reference) else { return nil }
        let ids = Set(images.filter { digestBody($0.id).hasPrefix(digestBody(reference)) }.map(\.id))
        return ids.count == 1 ? ids.first : nil
    }

    /// Remove dangling images, or with `all` every image not in `inUse`, then let the
    /// runtime drop the blobs nothing references any more.
    /// - Returns: the images removed and the bytes their digests freed (a digest another
    ///   name still points at frees nothing).
    public func prune(all: Bool, inUse: [String]) async throws -> (removed: [ImageInfo], reclaimed: UInt64) {
        var removed: [ImageInfo] = []
        for image in Self.pruneCandidates(try await list(), all: all, inUse: inUse) {
            removed.append(contentsOf: try await remove(image.reference).untagged)
        }
        // Orphaned blobs are garbage-collected by the CLI; the store API does not expose that.
        _ = try await RealProcessRunner().run(executable: Self.containerCLI, arguments: ["image", "prune"])

        let remaining = Set(try await list(enrich: false).map(\.id))
        var counted: Set<String> = []
        let reclaimed = removed
            .filter { !remaining.contains($0.id) && counted.insert($0.id).inserted }
            .reduce(UInt64(0)) { $0 + ($1.size ?? 0) }
        return (removed, reclaimed)
    }

    // MARK: - Tag

    /// Tag an image with a new reference.
    public func tag(_ source: String, _ target: String) async throws {
        let image = try await resolve(source)
        let dst = try Self.normalize(target)
        _ = try await imageStore.tag(existing: image.reference, new: dst)
    }

    // MARK: - Inspect

    /// Inspect an image reference, returning a Docker-compatible ImageInspect.
    public func inspect(_ reference: String, platform: String? = nil) async throws -> ImageInspect {
        let image = try await resolve(reference)
        let normalized = image.reference
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
        tags: [String], dockerfilePath: String, context: String, noCache: Bool = false,
        buildArgs: [String] = [], platforms: [String] = [], target: String? = nil,
        labels: [String] = [], quiet: Bool = false, progress: String? = nil,
        output: [String] = [], builder: String? = nil
    ) -> [String] {
        var args = ["build"]
        for t in tags { args += ["-t", t] }
        args += ["-f", dockerfilePath]
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

    /// Resolve a build `context` to an absolute path anchored to `cwd`.
    public static func resolveContextPath(context: String, cwd: String) -> String {
        guard !context.hasPrefix("/") else { return context }
        return URL(fileURLWithPath: cwd).appendingPathComponent(context).standardized.path
    }

    static func resolveDockerfilePath(context: String, dockerfile: String?, cwd: String) -> String {
        guard let dockerfile else {
            return URL(fileURLWithPath: context).appendingPathComponent("Dockerfile").standardized.path
        }
        if dockerfile.hasPrefix("/") {
            return dockerfile
        }
        return URL(fileURLWithPath: cwd).appendingPathComponent(dockerfile).standardized.path
    }

    /// Resolve a Compose service's `build.dockerfile` to an absolute path using Docker Compose semantics:
    /// relative `dockerfile` is relative to `build.context`, not the CWD.
    public static func composeDockerfilePath(context: String, dockerfile: String, cwd: String) -> String {
        let absContext = resolveContextPath(context: context, cwd: cwd)
        return resolveDockerfilePath(context: absContext, dockerfile: dockerfile, cwd: absContext)
    }

    /// Build an image from a Dockerfile using the `container` CLI.
    /// - Parameter platforms: pass multiple values to build a multi-arch manifest list (e.g. `["linux/amd64", "linux/arm64"]`).
    /// - Parameter builder: optional named builder instance forwarded to `container build --builder`,
    ///   enabling a remote BuildKit node for exotic architectures (apple/container#1496).
    public func build(tags: [String], context: String, dockerfile: String? = nil, noCache: Bool = false, buildArgs: [String] = [], platforms: [String] = [], target: String? = nil, labels: [String] = [], quiet: Bool = false, progress: String? = nil, output: [String] = [], builder: String? = nil) async throws -> ImageInfo {
        // The first tag is the one the built image is looked up under.
        guard let tag = tags.first else {
            throw MockerError.buildError("No image name given for the build")
        }
        let absContext = Self.resolveContextPath(context: context, cwd: FileManager.default.currentDirectoryPath)
        let dockerfilePath = Self.resolveDockerfilePath(
            context: absContext,
            dockerfile: dockerfile,
            cwd: FileManager.default.currentDirectoryPath
        )

        guard FileManager.default.fileExists(atPath: dockerfilePath) else {
            throw MockerError.buildError("Dockerfile not found at \(dockerfilePath)")
        }

        let args = Self.makeBuildArguments(
            tags: tags, dockerfilePath: dockerfilePath, context: context, noCache: noCache,
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

        // Fetch real image info from the store after build. `container build -t <tag>`
        // stores the literal tag, so this must resolve verbatim-first too.
        if let image = try? await resolve(tag) {
            return await Self.toImageInfo(image)
        }

        // The build succeeded but the image is not indexed in the store we can read.
        // Report what is known instead of inventing a digest, size and timestamp.
        let ref = try ImageReference.parse(tag)
        return ImageInfo(id: "", repository: ref.fullRepository, tag: ref.tag)
    }

    // MARK: - Push

    /// Push an image to a registry.
    /// - Parameter platform: optional `linux/amd64`-style filter; nil pushes the full manifest list.
    public func push(_ reference: String, platform: String? = nil) async throws {
        // The image is found the way the user spelled it (a local build is stored under
        // its bare tag), but the push target must be the registry-qualified reference —
        // it is also the key RegistryAuth resolves credentials with. Tag the local image
        // under that name first, otherwise the store has nothing to push.
        let image = try await resolve(reference)
        let normalized = try Self.normalize(reference)
        if image.reference != normalized {
            // Must not be swallowed: pushing after a failed tag would upload whatever
            // image that reference already points at.
            _ = try await imageStore.tag(existing: image.reference, new: normalized)
        }
        let parsedPlatform = try platform.map { try ContainerizationOCI.Platform(from: $0) }
        try await imageStore.push(
            reference: normalized, platform: parsedPlatform, auth: RegistryAuth.resolve(for: normalized)
        )
    }

    // MARK: - Save / Load

    /// Save images to an OCI tar archive.
    public func save(references: [String], to outputPath: String) async throws {
        var normalizedRefs: [String] = []
        for reference in references {
            normalizedRefs.append(try await resolve(reference).reference)
        }
        let outputURL = URL(fileURLWithPath: outputPath)
        try await imageStore.save(references: normalizedRefs, out: outputURL)
    }

    /// Load images from an OCI tar archive.
    public func load(from inputPath: String) async throws -> [ImageInfo] {
        let inputURL = URL(fileURLWithPath: inputPath)
        let images = try await imageStore.load(from: inputURL)
        var infos: [ImageInfo] = []
        for image in images {
            infos.append(await Self.toImageInfo(image))
        }
        return infos
    }

    // MARK: - Helpers

    /// The stored name of the local image an ID (full, truncated or hex prefix) refers to;
    /// nil when `reference` is not an ID or matches nothing. Ambiguity is an error, as for `rmi`.
    public func name(forID reference: String) async throws -> String? {
        guard Self.looksLikeDigest(reference) else { return nil }
        do {
            return try await resolve(reference).reference
        } catch MockerError.imageNotFound {
            return nil
        }
    }

    /// Look an image up the way the user spelled it, falling back to the normalized
    /// `docker.io/library/...` form.
    ///
    /// Store keys are whatever string created them: `container build -t caddy:latest`
    /// stores a bare reference while a pull stores a fully-qualified one. Normalizing
    /// first therefore matched a *different* image than the one named — `rmi caddy:latest`
    /// deleted the pulled base image instead of the local build.
    private func resolve(_ reference: String) async throws -> Containerization.Image {
        for candidate in Self.resolutionCandidates(reference) {
            if let hit = try? await imageStore.get(reference: candidate) {
                return hit
            }
        }
        // Nothing answered to the reference as a name. `mocker images -q` prints digests
        // (truncated by default), and `mocker images -q | xargs mocker rmi` is the usual
        // cleanup, so fall back to matching the stored digests by prefix.
        if Self.looksLikeDigest(reference) {
            let stored = (try? await imageStore.list()) ?? []
            let distinct = Self.matchingDigests(reference, in: stored.map(\.digest))
            if distinct.count > 1 {
                throw MockerError.operationFailed(
                    "image reference \(reference) is ambiguous: it matches \(distinct.count) images")
            }
            if let digest = distinct.first,
               let hit = stored.first(where: { $0.digest == digest }) {
                return hit
            }
        }
        throw MockerError.imageNotFound(reference)
    }

    /// Whether an argument should be tried as a digest: a full `sha256:...`, the truncated
    /// form `mocker images -q` prints, or a bare hex prefix as `docker rmi` accepts.
    static func looksLikeDigest(_ reference: String) -> Bool {
        let body = digestBody(reference)
        guard body.count >= 4 else { return false }
        return body.allSatisfy(\.isHexDigit)
    }

    /// Digests matching `reference` as a prefix, deduplicated: several tags of one image
    /// share a digest and are one image, not an ambiguity. Pure, so the matching and the
    /// ambiguity rule can be tested without a store.
    static func matchingDigests(_ reference: String, in digests: [String]) -> [String] {
        // `docker rmi` takes the ID with or without the algorithm prefix, so compare hex.
        let wanted = digestBody(reference).lowercased()
        var seen: Set<String> = []
        return digests
            .filter { digestBody($0).lowercased().hasPrefix(wanted) }
            .filter { seen.insert($0).inserted }
    }

    /// The hex part of a digest, with any `sha256:` prefix removed.
    static func digestBody(_ reference: String) -> String {
        reference.hasPrefix("sha256:") ? String(reference.dropFirst("sha256:".count)) : reference
    }

    /// Store keys to try, in order: exactly what the user typed, then the same with an
    /// implied `:latest`, then the normalized registry-qualified form. Pure, so the
    /// ordering that keeps `rmi` from deleting the wrong image is directly testable.
    static func resolutionCandidates(_ reference: String) -> [String] {
        var candidates = [reference]
        if !hasTag(reference) {
            candidates.append("\(reference):latest")
        }
        for normalized in [try? normalize(reference), try? normalize(hasTag(reference) ? reference : "\(reference):latest")] {
            if let normalized, !candidates.contains(normalized) {
                candidates.append(normalized)
            }
        }
        return candidates
    }

    /// Whether a reference carries an explicit tag (a colon after the last slash,
    /// so a registry port like `localhost:5000/app` doesn't count as one).
    static func hasTag(_ reference: String) -> Bool {
        let lastComponent = reference.split(separator: "/").last.map(String.init) ?? reference
        return lastComponent.contains(":")
    }

    /// Size and creation date of an image, read from its manifest and config.
    /// Returns nils when the metadata cannot be resolved, so callers surface the gap
    /// instead of reporting a confident zero.
    static func sizeAndCreated(of image: Containerization.Image) async -> (size: UInt64?, created: Date?) {
        guard let manifest = await manifestForListing(of: image) else { return (nil, nil) }
        let total = manifestSize(manifest)
        var created: Date?
        if let content = try? await image.getContent(digest: manifest.config.digest),
           let config: ContainerizationOCI.Image = try? content.decode(),
           let stamp = config.created {
            created = RelativeDate.parse(stamp)
        }
        return (UInt64(max(0, total)), created)
    }

    /// The manifest a listing should measure: the current platform's when present,
    /// otherwise the image's sole manifest (single-arch images).
    private static func manifestForListing(
        of image: Containerization.Image
    ) async -> ContainerizationOCI.Manifest? {
        if let matched = try? await image.manifest(for: ContainerizationOCI.Platform.current) {
            return matched
        }
        guard let index = try? await image.index(),
              let sole = soleManifestDescriptor(from: index.manifests),
              let content = try? await image.getContent(digest: sole.digest) else {
            return nil
        }
        return try? content.decode()
    }

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

    /// Repository/tag/digest only — no manifest or config reads.
    private static func basicImageInfo(_ image: Containerization.Image) -> ImageInfo {
        let ref = try? ImageReference.parse(image.reference)
        return ImageInfo(
            id: image.digest,
            repository: ref?.fullRepository ?? image.reference,
            tag: ref?.tag ?? "latest"
        )
    }

    private static func toImageInfo(_ image: Containerization.Image) async -> ImageInfo {
        // Parse repo and tag from the reference string
        let ref = try? ImageReference.parse(image.reference)
        let repository = ref?.fullRepository ?? image.reference
        let tag = ref?.tag ?? "latest"
        let metadata = await sizeAndCreated(of: image)

        return ImageInfo(
            id: image.digest,
            repository: repository,
            tag: tag,
            size: metadata.size,
            created: metadata.created
        )
    }
}
