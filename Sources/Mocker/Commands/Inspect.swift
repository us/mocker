import ArgumentParser
import MockerKit

enum InspectObjectType: String, ExpressibleByArgument {
    case image
    case container
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
        case auto
    }

    /// Single source of truth mapping the `--type` flag to an inspection target.
    /// Pure and injectable so routing can be unit-tested without runtime state.
    static func resolveKind(type: InspectObjectType?) -> Kind {
        switch type {
        case .image: return .image
        case .container: return .container
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
            var results: [MockerKit.ImageInspect] = []
            for target in targets {
                let info = try await imageManager.inspect(target, platform: platform)
                results.append(info)
            }
            try TableFormatter.printJSONArray(results, escapeSlashes: false)

        case .container:
            for target in targets {
                guard let container = try? await engine.inspect(target) else {
                    throw MockerError.containerNotFound(target)
                }
                try TableFormatter.printJSONArray(container)
            }

        case .auto:
            // Container-first fallback when --type is not specified
            for target in targets {
                if let container = try? await engine.inspect(target) {
                    try TableFormatter.printJSONArray(container)
                } else {
                    do {
                        let image = try await imageManager.inspect(target, platform: platform)
                        try TableFormatter.printJSONArray(image, escapeSlashes: false)
                    } catch {
                        if platform != nil {
                            throw error
                        }
                        throw MockerError.containerNotFound(target)
                    }
                }
            }
        }
    }
}
