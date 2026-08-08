import Testing
import Foundation
@testable import MockerKit

@Suite("Compose volume lifecycle")
struct ComposeVolumeLifecycleTests {
    private func parse(_ yaml: String) throws -> ComposeFile {
        try ComposeFile.parse(yaml)
    }

    @Test("external: true is parsed, and defaults to false")
    func parsesExternal() throws {
        let compose = try parse("""
        volumes:
          shared:
            external: true
          owned:
        """)

        #expect(compose.volumes["shared"]?.external == true)
        #expect(compose.volumes["owned"]?.external == false)
    }

    @Test("Legacy external mapping form is treated as external")
    func parsesLegacyExternalMapping() throws {
        let compose = try parse("""
        volumes:
          shared:
            external:
              name: already-there
        """)

        #expect(compose.volumes["shared"]?.external == true)
        #expect(compose.volumes["shared"]?.runtimeName(projectName: "proj") == "already-there")
    }

    @Test("An explicit name: is used verbatim, without the project prefix")
    func explicitNameWins() throws {
        let compose = try parse("""
        volumes:
          data:
            name: shared-data
        """)

        #expect(compose.volumes["data"]?.runtimeName(projectName: "proj") == "shared-data")
    }

    @Test("Project-owned volumes are namespaced")
    func ownedVolumeIsNamespaced() throws {
        let compose = try parse("volumes:\n  data:\n")

        #expect(compose.volumes["data"]?.runtimeName(projectName: "proj") == "proj-data")
    }

    @Test("down --volumes removes owned volumes only")
    func volumesToRemoveSkipsExternal() throws {
        let compose = try parse("""
        volumes:
          data:
          cache:
          shared:
            external: true
          named:
            name: custom-name
        """)

        let removals = ComposeOrchestrator.volumesToRemove(composeFile: compose, projectName: "proj")

        #expect(removals == ["proj-cache", "proj-data", "custom-name"])
    }

    @Test("A project with no volumes removes nothing")
    func volumesToRemoveEmpty() throws {
        let compose = try parse("services:\n  web:\n    image: nginx\n")

        #expect(ComposeOrchestrator.volumesToRemove(composeFile: compose, projectName: "proj").isEmpty)
    }

    @Test("up creates owned volumes and never external ones")
    func volumesToCreateSkipsExternal() throws {
        let compose = try parse("""
        volumes:
          data:
          shared:
            external: true
          named:
            name: custom-name
        """)

        let created = ComposeOrchestrator.volumesToCreate(composeFile: compose, projectName: "proj")

        #expect(created.map(\.name) == ["proj-data", "custom-name"])
        #expect(created.allSatisfy { $0.driver == "local" })
    }

    @Test("Volume names that would escape the volumes directory are rejected", arguments: [
        "../etc", "a/b", "..", ".", "",
    ])
    func rejectsEscapingVolumeNames(name: String) {
        #expect(throws: MockerError.self) {
            try VolumeManager.validateName(name)
        }
    }

    @Test("Ordinary volume names are accepted", arguments: ["proj-data", "custom_name", "-legacy"])
    func acceptsOrdinaryVolumeNames(name: String) {
        #expect(throws: Never.self) {
            try VolumeManager.validateName(name)
        }
    }
}
