/// Inspects each target image and returns the per-target `ImageInspect` results.
///
/// - Parameters:
///   - targets: Image names or IDs to inspect.
///   - platform: Optional platform string forwarded to the manager.
///   - manager: The `ImageManager` used to resolve each target.
/// - Returns: One `ImageInspect` per target, preserving input order.
public func inspectImages(
    targets: [String],
    platform: String?,
    manager: ImageManager
) async throws -> [ImageInspect] {
    var results: [ImageInspect] = []
    for target in targets {
        let info = try await manager.inspect(target, platform: platform)
        results.append(info)
    }
    return results
}

/// Inspects each target container and returns Docker-compatible `ContainerInspect` results.
///
/// - Parameters:
///   - targets: Container names or IDs to inspect.
///   - engine: The `ContainerEngine` used to resolve each target.
/// - Returns: One `ContainerInspect` per target, preserving input order.
/// - Throws: `MockerError.containerNotFound` when a target cannot be resolved.
public func inspectContainers(
    targets: [String],
    engine: ContainerEngine
) async throws -> [ContainerInspect] {
    var results: [ContainerInspect] = []
    for target in targets {
        guard let container = try? await engine.inspect(target) else {
            throw MockerError.containerNotFound(target)
        }
        results.append(mapToContainerInspect(container))
    }
    return results
}
