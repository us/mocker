import Testing
import ArgumentParser
import Darwin
import Foundation
import MockerKit
@testable import Mocker

@Suite("ImageInspect CLI Tests")
struct ImageInspectCLITests {

    // MARK: - Inspect --type routing

    @Test("--type image routes to image inspect")
    func typeImageIsImage() throws {
        let command = try Inspect.parse(["--type", "image", "nginx"])
        #expect(command.type == .image)
    }

    @Test("--type container routes to container inspect")
    func typeContainerIsContainer() throws {
        let command = try Inspect.parse(["--type", "container", "nginx"])
        #expect(command.type == .container)
    }

    @Test("omitting --type leaves type nil (container-first fallback)")
    func typeNilWhenOmitted() throws {
        let command = try Inspect.parse(["nginx"])
        #expect(command.type == nil)
    }

    // MARK: - Inspect.resolveKind routing decision

    @Test("resolveKind maps type=image to .image")
    func resolveKindImage() {
        #expect(Inspect.resolveKind(type: .image) == .image)
    }

    @Test("resolveKind maps type=container to .container")
    func resolveKindContainer() {
        #expect(Inspect.resolveKind(type: .container) == .container)
    }

    @Test("--type rejects unsupported values")
    func typeRejectsUnsupportedValues() {
        #expect(throws: Error.self) {
            _ = try Inspect.parse(["--type", "volume", "nginx"])
        }
    }

    @Test("resolveKind maps nil type to .auto (container-first)")
    func resolveKindAuto() {
        #expect(Inspect.resolveKind(type: nil) == .auto)
    }

    // MARK: - ImageInspect --platform

    @Test("--platform is forwarded to ImageInspect command")
    func platformOptionParsed() throws {
        let command = try ImageInspect.parse(["--platform", "linux/amd64", "nginx"])
        #expect(command.platform == "linux/amd64")
    }

    @Test("top-level inspect parses --platform without --type")
    func inspectPlatformOptionParsedInAutoMode() throws {
        let command = try Inspect.parse(["--platform", "linux/amd64", "nginx"])
        #expect(command.type == nil)
        #expect(command.platform == "linux/amd64")
    }

    @Test("image inspect formatter emits Docker-style JSON array")
    func imageInspectFormatterEmitsJSONArray() throws {
        let inspect = MockerKit.ImageInspect(
            id: "sha256:config",
            repoTags: ["docker.io/library/nginx:latest"],
            repoDigests: ["docker.io/library/nginx@sha256:index"],
            created: "2024-11-19T17:01:02Z",
            architecture: "arm64",
            os: "linux",
            size: 42,
            config: ImageInspectConfig(env: ["PATH=/usr/bin"]),
            rootFS: ImageInspectRootFS(type: "layers", layers: ["sha256:layer"])
        )

        let output = try captureStdout {
            try TableFormatter.printJSONArray([inspect], escapeSlashes: false)
        }

        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("["))
        #expect(output.contains("\"RepoTags\""))
        #expect(output.contains("docker.io/library/nginx:latest"))
        #expect(!output.contains("docker.io\\/library\\/nginx"))
    }
}

private func captureStdout(_ body: () throws -> Void) throws -> String {
    let pipe = Pipe()
    let original = dup(STDOUT_FILENO)
    precondition(original >= 0)
    fflush(stdout)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

    do {
        try body()
        fflush(stdout)
        dup2(original, STDOUT_FILENO)
        close(original)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    } catch {
        fflush(stdout)
        dup2(original, STDOUT_FILENO)
        close(original)
        pipe.fileHandleForWriting.closeFile()
        throw error
    }
}
