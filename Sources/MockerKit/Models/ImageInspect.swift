import Foundation
import ContainerizationOCI

// MARK: - Docker-Compatible ImageInspect DTOs

/// Docker-compatible image inspect output (mirrors `moby/moby` ImageInspect struct).
/// Serializes with Docker PascalCase JSON keys; optional fields are omitted when absent.
public struct ImageInspect: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case repoTags = "RepoTags"
        case repoDigests = "RepoDigests"
        case created = "Created"
        case author = "Author"
        case architecture = "Architecture"
        case variant = "Variant"
        case os = "Os"
        case osVersion = "OsVersion"
        case size = "Size"
        case config = "Config"
        case rootFS = "RootFS"
    }

    public let id: String
    public let repoTags: [String]
    public let repoDigests: [String]
    /// RFC3339Nano pass-through from OCI config. Omitted when the OCI config has no created field.
    public let created: String?
    public let author: String?
    public let architecture: String
    public let variant: String?
    public let os: String
    public let osVersion: String?
    /// Σ manifest layer sizes + config blob size (no blob reads).
    public let size: Int64
    /// Always emitted; an empty object `{}` for config-less images (Docker parity).
    public let config: ImageInspectConfig
    public let rootFS: ImageInspectRootFS

    public init(
        id: String,
        repoTags: [String],
        repoDigests: [String],
        created: String? = nil,
        author: String? = nil,
        architecture: String,
        variant: String? = nil,
        os: String,
        osVersion: String? = nil,
        size: Int64,
        config: ImageInspectConfig,
        rootFS: ImageInspectRootFS
    ) {
        self.id = id
        self.repoTags = repoTags
        self.repoDigests = repoDigests
        self.created = created
        self.author = author
        self.architecture = architecture
        self.variant = variant
        self.os = os
        self.osVersion = osVersion
        self.size = size
        self.config = config
        self.rootFS = rootFS
    }
}

/// Docker-compatible Config sub-object. All fields are optional; absent fields are omitted.
public struct ImageInspectConfig: Codable, Sendable {
    // Explicit PascalCase CodingKeys mirror Docker's ImageConfig JSON contract.
    enum CodingKeys: String, CodingKey {
        case user = "User"
        case env = "Env"
        case exposedPorts = "ExposedPorts"
        case entrypoint = "Entrypoint"
        case cmd = "Cmd"
        case volumes = "Volumes"
        case workingDir = "WorkingDir"
        case labels = "Labels"
        case stopSignal = "StopSignal"
    }

    public let user: String?
    public let env: [String]?
    public let exposedPorts: [String: ImageInspectEmptyObject]?
    public let entrypoint: [String]?
    public let cmd: [String]?
    public let volumes: [String: ImageInspectEmptyObject]?
    public let workingDir: String?
    public let labels: [String: String]?
    public let stopSignal: String?

    public init(
        user: String? = nil,
        env: [String]? = nil,
        exposedPorts: [String: ImageInspectEmptyObject]? = nil,
        entrypoint: [String]? = nil,
        cmd: [String]? = nil,
        volumes: [String: ImageInspectEmptyObject]? = nil,
        workingDir: String? = nil,
        labels: [String: String]? = nil,
        stopSignal: String? = nil
    ) {
        self.user = user
        self.env = env
        self.exposedPorts = exposedPorts
        self.entrypoint = entrypoint
        self.cmd = cmd
        self.volumes = volumes
        self.workingDir = workingDir
        self.labels = labels
        self.stopSignal = stopSignal
    }
}

/// Encodes Docker's map[string]struct{} values, for example `"80/tcp": {}`.
public struct ImageInspectEmptyObject: Codable, Sendable, Equatable {
    public init() {}
}

/// Extra config fields not currently surfaced by ContainerizationOCI.ImageConfig.
public struct ImageInspectConfigExtras: Codable, Sendable, Equatable {
    public let exposedPorts: [String: ImageInspectEmptyObject]?
    public let volumes: [String: ImageInspectEmptyObject]?

    public init(
        exposedPorts: [String: ImageInspectEmptyObject]? = nil,
        volumes: [String: ImageInspectEmptyObject]? = nil
    ) {
        self.exposedPorts = exposedPorts
        self.volumes = volumes
    }
}

/// Docker-compatible RootFS sub-object.
public struct ImageInspectRootFS: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case layers = "Layers"
    }

    public let type: String
    /// Equals OCI config rootfs.diff_ids.
    public let layers: [String]

    public init(type: String, layers: [String]) {
        self.type = type
        self.layers = layers
    }
}

// MARK: - Pure Mapping Function

/// Maps OCI manifest + config to a Docker-compatible `ImageInspect`. Pure, no I/O.
///
/// - Parameters:
///   - config: Decoded OCI image config (`application/vnd.oci.image.config.v1+json`).
///   - manifest: Decoded OCI image manifest for the resolved platform.
///   - reference: Fully-qualified image reference (e.g. `docker.io/library/nginx:latest`).
///   - indexDigest: Index (multi-arch) digest used for `RepoDigests` (`image.digest`).
///   - configExtras: Config fields decoded from the raw OCI config JSON but not exposed
///     by `ContainerizationOCI.ImageConfig`.
///   - overrideRepoTags: Local image-store tags to report. When absent, derived from
///     `reference` for compatibility with pure mapping tests.
///   - overrideRepoDigests: Local image-store repo digests to report. When absent,
///     derived from `reference` for compatibility with pure mapping tests.
/// - Returns: A populated `ImageInspect` ready for JSON serialisation.
public func mapToImageInspect(
    config: ContainerizationOCI.Image,
    manifest: ContainerizationOCI.Manifest,
    reference: String,
    indexDigest: String,
    configExtras: ImageInspectConfigExtras? = nil,
    repoTags overrideRepoTags: [String]? = nil,
    repoDigests overrideRepoDigests: [String]? = nil
) -> ImageInspect {
    // Id is the config blob digest, not the index digest — Docker parity for single-platform inspect.
    let id = manifest.config.digest

    let size = manifest.layers.reduce(0) { $0 + $1.size } + manifest.config.size

    let repoTags = overrideRepoTags ?? extractRepoTags(from: reference)
    let repo = extractRepo(from: reference)
    let repoDigests = overrideRepoDigests ?? ["\(repo)@\(indexDigest)"]

    // Docker always emits Config; fall back to an empty object for config-less images.
    let inspectConfig = config.config.map { ociConfig in
        ImageInspectConfig(
            user: ociConfig.user,
            env: ociConfig.env,
            exposedPorts: configExtras?.exposedPorts,
            entrypoint: ociConfig.entrypoint,
            cmd: ociConfig.cmd,
            volumes: configExtras?.volumes,
            workingDir: ociConfig.workingDir,
            labels: ociConfig.labels,
            stopSignal: ociConfig.stopSignal
        )
    } ?? ImageInspectConfig(
        exposedPorts: configExtras?.exposedPorts,
        volumes: configExtras?.volumes
    )

    let rootFS = ImageInspectRootFS(
        type: "layers",
        layers: config.rootfs.diffIDs
    )

    return ImageInspect(
        id: id,
        repoTags: repoTags,
        repoDigests: repoDigests,
        created: config.created,
        author: config.author,
        architecture: config.architecture,
        variant: config.variant,
        os: config.os,
        osVersion: config.osVersion,
        size: size,
        config: inspectConfig,
        rootFS: rootFS
    )
}

func decodeImageInspectConfigExtras(from data: Data) throws -> ImageInspectConfigExtras {
    struct RawImageConfig: Decodable {
        struct RawConfig: Decodable {
            enum CodingKeys: String, CodingKey {
                case exposedPorts = "ExposedPorts"
                case volumes = "Volumes"
            }

            let exposedPorts: [String: ImageInspectEmptyObject]?
            let volumes: [String: ImageInspectEmptyObject]?
        }

        let config: RawConfig?
    }

    let raw = try JSONDecoder().decode(RawImageConfig.self, from: data)
    return ImageInspectConfigExtras(
        exposedPorts: raw.config?.exposedPorts,
        volumes: raw.config?.volumes
    )
}

// MARK: - Reference Parsing Helpers

/// Returns the `repo:tag` portion for tagged references, or `[]` for pure digest references.
private func extractRepoTags(from reference: String) -> [String] {
    guard let atIndex = reference.firstIndex(of: "@") else {
        return [reference]
    }
    // For digest references, RepoTags carries the tag portion before "@" (empty when untagged).
    let beforeAt = String(reference[reference.startIndex..<atIndex])
    return referenceHasTag(beforeAt) ? [beforeAt] : []
}

/// Detects a tag by looking for ":" in the last path component, ignoring registry host ports.
private func referenceHasTag(_ reference: String) -> Bool {
    let lastComponent = reference
        .split(separator: "/", omittingEmptySubsequences: false)
        .last
        .map(String.init) ?? reference
    return lastComponent.contains(":")
}

/// Extracts the repository portion of a reference (strips tag and digest).
private func extractRepo(from reference: String) -> String {
    // Strip digest suffix first
    let withoutDigest: String
    if let atIndex = reference.firstIndex(of: "@") {
        withoutDigest = String(reference[reference.startIndex..<atIndex])
    } else {
        withoutDigest = reference
    }
    // Strip tag suffix — find last ":" that is not part of a port in a registry host
    // Strategy: split by "/" and strip ":" from the last component only
    var parts = withoutDigest.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    if var last = parts.last, let colonIndex = last.lastIndex(of: ":") {
        last = String(last[last.startIndex..<colonIndex])
        parts[parts.count - 1] = last
    }
    return parts.joined(separator: "/")
}
