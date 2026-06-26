import Testing
@testable import MockerKit

@Suite("InspectOperations Tests")
struct InspectOperationsTests {

    @Test("inspectImages exists with documented signature")
    func inspectImagesSignatureExists() async throws {
        let manager = try ImageManager(config: MockerConfig())
        let _: [MockerKit.ImageInspect] = try await inspectImages(
            targets: [],
            platform: nil,
            manager: manager
        )
    }

    @Test("inspectContainers exists with documented signature")
    func inspectContainersSignatureExists() async throws {
        let engine = try ContainerEngine(config: MockerConfig())
        let _: [ContainerInspect] = try await inspectContainers(
            targets: [],
            engine: engine
        )
    }
}
