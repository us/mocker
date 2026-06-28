import ArgumentParser
import MockerKit

enum InspectObjectType: String, ExpressibleByArgument {
    case image
    case container
    case network
}

struct Inspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Return low-level information on container or image"
    )

    @Argument(help: "Container or image name/ID")
    var targets: [String]

    @Option(name: .shortAndLong, help: "Format output using a custom template")
    var format: String?

    @Option(name: .long, help: "Only inspect objects of the given type (image or container)")
    var type: InspectObjectType?

    @Option(name: .long, help: "Inspect a specific platform of a multi-platform image")
    var platform: String?

    @Flag(name: .shortAndLong, help: "Display total file sizes if the type is container")
    var size = false

    /// The resolved inspection target derived from `--type`.
    enum Kind: Equatable {
        case image
        case container
        case network
        case auto
    }

    /// Single source of truth mapping the `--type` flag to an inspection target.
    /// Pure and injectable so routing can be unit-tested without runtime state.
    static func resolveKind(type: InspectObjectType?) -> Kind {
        switch type {
        case .image: return .image
        case .container: return .container
        case .network: return .network
        case nil: return .auto
        }
    }

    // MARK: - Run

    func run() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()

        let engine = try ContainerEngine(config: config)
        let imageManager = try ImageManager(config: config)

        switch Self.resolveKind(type: type) {
        case .image:
            let results = try await inspectImages(targets: targets, platform: platform, manager: imageManager)
            try InspectFormat.emitArray(results, format: format)

        case .container:
            let results = try await inspectContainers(targets: targets, engine: engine)
            try InspectFormat.emitArray(results, format: format)

        case .network:
            let networkManager = try NetworkManager(config: config)
            let results = try await inspectNetworks(targets: targets, manager: networkManager)
            try InspectFormat.emitArray(results, format: format)

        case .auto:
            for target in targets {
                if let container = try? await engine.inspect(target) {
                    try InspectFormat.emitOne(mapToContainerInspect(container), format: format)
                } else {
                    do {
                        let image = try await imageManager.inspect(target, platform: platform)
                        try InspectFormat.emitOne(image, format: format)
                    } catch {
                        // 3rd attempt: network (--platform accepted for image targets only; ignored for network — Docker parity)
                        let networkManager = try NetworkManager(config: config)
                        do {
                            let info = try await networkManager.inspect(target)
                            try InspectFormat.emitOne(mapToNetworkInspect(info), format: format)
                        } catch {
                            if platform != nil { throw error }
                            throw MockerError.networkNotFound(target)
                        }
                    }
                }
            }
        }
    }
}
