import Testing
import Foundation
@testable import MockerKit

/// Named volumes used to be host directories mounted over virtiofs, where the guest
/// cannot chown (issue #92). These tests pin that volumes go to the runtime's native
/// store while directory volumes (shared by services, or from earlier releases) keep working.
@Suite("VolumeManager")
struct VolumeManagerTests {
    /// Shape of a real `container volume ls --format json` response (runtime 1.5.0).
    private let listJSON = """
    [{"configuration":{"creationDate":"2026-09-30T14:56:58Z","driver":"local","format":"ext4",
      "labels":{"com.apple.container.resource.anonymous":""},"name":"c929dff6","options":{},
      "source":"/vols/c929dff6/volume.img"},"id":"c929dff6"},
     {"configuration":{"creationDate":"2026-09-30T14:50:26Z","driver":"local","format":"ext4",
      "labels":{"team":"infra"},"name":"shared","options":{},
      "source":"/vols/shared/volume.img"},"id":"shared"}]
    """

    /// A data root holding one directory volume per name, `_data` only (no meta.json).
    private func dataRoot(directories: [String] = []) throws -> MockerConfig {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mocker-volume-tests-\(UUID().uuidString)").path
        for name in directories {
            try FileManager.default.createDirectory(
                atPath: "\(root)/volumes/\(name)/_data", withIntermediateDirectories: true)
        }
        return MockerConfig(dataRoot: root)
    }

    @Test("Listing maps the runtime's JSON onto VolumeInfo")
    func parsesListing() {
        let volumes = VolumeManager.parseVolumes(listJSON)

        #expect(volumes.map(\.name) == ["c929dff6", "shared"])
        #expect(volumes[1].labels["team"] == "infra")
        #expect(volumes[1].mountpoint == "/vols/shared/volume.img")
        #expect(VolumeManager.parseVolumes("not json").isEmpty)
    }

    @Test("create passes labels through to the runtime")
    func createForwardsLabels() async throws {
        let runner = MockProcessRunner(responses: [("", 0), (listJSON, 0)])
        let manager = try VolumeManager(config: dataRoot(), runner: runner, cli: "/usr/bin/container")

        _ = try await manager.create(name: "shared", labels: ["team": "infra"])

        let calls = await runner.calls
        #expect(calls.first?.arguments == ["volume", "create", "--label", "team=infra", "shared"])
    }

    @Test("A name the runtime would reject fails before anything is created",
          arguments: ["_x", "my data", "-lead"])
    func rejectsRuntimeInvalidNames(name: String) async throws {
        let runner = MockProcessRunner()
        let manager = try VolumeManager(config: dataRoot(), runner: runner, cli: "/usr/bin/container")

        await #expect(throws: MockerError.self) { try await manager.create(name: name) }
        #expect(await runner.calls.isEmpty)
    }

    @Test("create never shadows a directory volume with a native volume of the same name")
    func createRefusesDirectoryName() async throws {
        let runner = MockProcessRunner()
        let manager = try VolumeManager(
            config: dataRoot(directories: ["proj_old"]), runner: runner, cli: "/usr/bin/container")

        await #expect(throws: MockerError.self) { try await manager.create(name: "proj_old") }
        #expect(await runner.calls.isEmpty)
    }

    @Test("A directory volume wins a name collision and is listed without meta.json")
    func directoryMergedAndWins() async throws {
        let config = try dataRoot(directories: ["shared", "old"])
        let manager = try VolumeManager(
            config: config, runner: MockProcessRunner(responses: [(listJSON, 0)]), cli: "/usr/bin/container")

        let volumes = try await manager.list()

        #expect(volumes.map(\.name) == ["c929dff6", "old", "shared"])
        #expect(volumes.first { $0.name == "shared" }?.mountpoint == "\(config.volumesPath)/shared/_data")
    }

    @Test("remove deletes a directory volume and sends a native volume to the runtime")
    func removeRouting() async throws {
        let config = try dataRoot(directories: ["old"])
        let runner = MockProcessRunner(responses: [(listJSON, 0)])
        let manager = try VolumeManager(config: config, runner: runner, cli: "/usr/bin/container")

        _ = try await manager.remove("old")
        #expect(!FileManager.default.fileExists(atPath: "\(config.volumesPath)/old"))
        #expect(await runner.calls.map(\.arguments) == [["volume", "ls", "--format", "json"]])

        _ = try await manager.remove("shared")
        #expect(await runner.calls.last?.arguments == ["volume", "delete", "shared"])

        await #expect(throws: MockerError.self) { try await manager.remove("missing") }
    }

    @Test("prune removes only anonymous native volumes unless all is set, never directory ones")
    func pruneScope() async throws {
        func prune(all: Bool, directories: [String] = [], deleteStatus: Int32 = 0) async throws -> ([String], [[String]]) {
            let runner = MockProcessRunner(responses: [(listJSON, 0), ("", deleteStatus)])
            let manager = try VolumeManager(
                config: dataRoot(directories: directories), runner: runner, cli: "/usr/bin/container")
            let removed = try await manager.prune(all: all)
            return (removed, await runner.calls.dropFirst().map(\.arguments))
        }

        let anonymous = try await prune(all: false)
        #expect(anonymous.0 == ["c929dff6"])
        #expect(anonymous.1 == [["volume", "delete", "c929dff6"]])
        #expect(try await prune(all: true).0 == ["c929dff6", "shared"])
        #expect(try await prune(all: true, directories: ["shared"]).0 == ["c929dff6"])
        // A volume the runtime refuses to delete (in use) is not reported as removed.
        #expect(try await prune(all: true, deleteStatus: 1).0.isEmpty)
    }

    @Test("createDirectory makes a shareable volume compose mounts by path")
    func createDirectory() async throws {
        let config = try dataRoot()
        let runner = MockProcessRunner()
        let manager = try VolumeManager(config: config, runner: runner, cli: "/usr/bin/container")

        _ = try await manager.createDirectory(name: "proj_static")

        #expect(try manager.composeSource("proj_static") == "\(config.volumesPath)/proj_static/_data")
        #expect(FileManager.default.fileExists(atPath: "\(config.volumesPath)/proj_static/meta.json"))
        #expect(await runner.calls.isEmpty)
        await #expect(throws: MockerError.self) { try await manager.createDirectory(name: "proj_static") }
    }

    @Test("compose mounts a directory volume by path and a native one by name")
    func composeSource() throws {
        let config = try dataRoot(directories: ["proj_old"])
        let manager = try VolumeManager(config: config, runner: MockProcessRunner(), cli: "/usr/bin/container")

        #expect(try manager.composeSource("proj_old") == "\(config.volumesPath)/proj_old/_data")
        #expect(try manager.composeSource("proj_new") == "proj_new")
        #expect(throws: MockerError.self) { try manager.composeSource("../escape") }
    }
}
