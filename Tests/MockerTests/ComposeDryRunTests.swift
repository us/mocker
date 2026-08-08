import Testing
import Foundation
import ArgumentParser
import MockerKit
@testable import Mocker

/// `--dry-run` was declared on every compose subcommand and read by none, so
/// `compose build --dry-run` really built and tagged an image (#74). These tests lock in
/// that the flag still parses everywhere it used to, that a dry run returns before
/// reaching the runtime, and which targets it reports.
@Suite("Compose dry-run")
struct ComposeDryRunTests {
    private func composeFile(_ body: String = "services:\n  web:\n    image: nginx:latest\n") throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("compose.yaml")
        try body.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @Test("Mutating subcommands accept --dry-run")
    func mutatingSubcommandsParseFlag() throws {
        let file = try composeFile().path

        #expect(try ComposeUp.parse(["-f", file, "--dry-run"]).options.dryRun)
        #expect(try ComposeDown.parse(["-f", file, "--dry-run"]).options.dryRun)
        #expect(try ComposeBuildCommand.parse(["-f", file, "--dry-run"]).options.dryRun)
        #expect(try ComposePull.parse(["-f", file, "--dry-run"]).options.dryRun)
        #expect(try ComposeStop.parse(["-f", file, "--dry-run"]).options.dryRun)
    }

    @Test("Subcommands without shared options still accept --dry-run")
    func standaloneSubcommandsParseFlag() throws {
        #expect(try ComposeLs.parse(["--dry-run"]).dryRun)
        #expect(try ComposeVersion.parse(["--dry-run"]).dryRun)
    }

    @Test("Read-only subcommands accept --dry-run")
    func readOnlySubcommandsParseFlag() throws {
        let file = try composeFile().path

        #expect(try ComposePS.parse(["-f", file, "--dry-run"]).options.dryRun)
        #expect(try ComposeConfig.parse(["-f", file, "--dry-run"]).options.dryRun)
    }

    @Test("A dry-run up returns before touching the runtime")
    func dryRunUpTouchesNothing() async throws {
        let file = try composeFile()

        var command = try ComposeUp.parse(["-f", file.path, "--dry-run", "-d"])
        command.options.projectName = "dryproj"

        // Reaching the runtime would mean constructing the engine and shelling out to
        // `container`; returning cleanly here is what proves the guard comes first.
        try await command.run()
    }

    @Test("Dry-run targets name the project's containers")
    func dryRunTargets() throws {
        let compose = try ComposeFile.parse("""
        services:
          web:
            image: nginx
          db:
            image: postgres
        """)

        #expect(ComposeStop.dryRunTargets(compose, "proj", []) == ["proj-db-1", "proj-web-1"])
        #expect(ComposeStop.dryRunTargets(compose, "proj", ["web"]) == ["proj-web-1"])
    }
}
