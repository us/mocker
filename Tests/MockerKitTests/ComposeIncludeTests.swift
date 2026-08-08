import Testing
import Foundation
@testable import MockerKit

@Suite("Compose include:")
struct ComposeIncludeTests {
    private func load(_ files: [ComposeTestHelpers.FileSpec], entry: String = "compose.yaml") throws -> (ComposeFile, URL) {
        let root = try ComposeTestHelpers.makeProjectDir(files)
        let file = try ComposeFile.load(from: root.appendingPathComponent(entry).path, projectDir: root)
        return (file, root)
    }

    @Test("Short-form include pulls in the included services")
    func shortForm() throws {
        let (compose, _) = try load([
            .file("compose.yaml", """
            include:
              - svc/compose.yaml
            """),
            .file("svc/compose.yaml", """
            services:
              hello:
                image: alpine:3.20
            """),
        ])

        #expect(compose.services["hello"]?.image == "alpine:3.20")
    }

    @Test("Long-form include accepts a path list")
    func longFormPathList() throws {
        let (compose, _) = try load([
            .file("compose.yaml", """
            include:
              - path:
                  - a/compose.yaml
                  - b/compose.yaml
            """),
            .file("a/compose.yaml", "services:\n  a:\n    image: alpine:3.20\n"),
            .file("b/compose.yaml", "services:\n  b:\n    image: busybox:1.37\n"),
        ])

        #expect(compose.services.keys.sorted() == ["a", "b"])
    }

    @Test("Parent's own definition overrides an included one")
    func parentWins() throws {
        let (compose, _) = try load([
            .file("compose.yaml", """
            include:
              - svc/compose.yaml
            services:
              hello:
                image: parent:1.0
            """),
            .file("svc/compose.yaml", "services:\n  hello:\n    image: included:1.0\n"),
        ])

        #expect(compose.services["hello"]?.image == "parent:1.0")
    }

    @Test("Included file's relative bind mount anchors to its own directory")
    func relativeBindMountAnchoring() throws {
        let (compose, root) = try load([
            .file("compose.yaml", "include:\n  - svc/compose.yaml\n"),
            .file("svc/compose.yaml", """
            services:
              hello:
                image: alpine:3.20
                volumes:
                  - ./data:/data
            """),
        ])

        let expected = root.appendingPathComponent("svc/data").standardized.path
        #expect(compose.services["hello"]?.volumes == ["\(expected):/data"])
    }

    @Test("project_directory overrides where relative bind mounts anchor")
    func projectDirectoryOverride() throws {
        let (compose, root) = try load([
            .file("compose.yaml", """
            include:
              - path: svc/compose.yaml
                project_directory: .
            """),
            .file("svc/compose.yaml", """
            services:
              hello:
                image: alpine:3.20
                volumes:
                  - ./data:/data
            """),
        ])

        let expected = root.appendingPathComponent("data").standardized.path
        #expect(compose.services["hello"]?.volumes == ["\(expected):/data"])
    }

    @Test("Named and absolute volume specs are left alone")
    func nonRelativeVolumesUntouched() throws {
        let (compose, _) = try load([
            .file("compose.yaml", "include:\n  - svc/compose.yaml\n"),
            .file("svc/compose.yaml", """
            services:
              hello:
                image: alpine:3.20
                volumes:
                  - data:/var/lib/data
                  - /etc/hosts:/etc/hosts
            """),
        ])

        #expect(compose.services["hello"]?.volumes == ["data:/var/lib/data", "/etc/hosts:/etc/hosts"])
    }

    @Test("Include uses its own env_file for interpolation")
    func perIncludeEnvFile() throws {
        let (compose, _) = try load([
            .file("compose.yaml", "include:\n  - path: svc/compose.yaml\n    env_file: custom.env\n"),
            .file("svc/custom.env", "TAG=3.21\n"),
            .file("svc/compose.yaml", "services:\n  hello:\n    image: alpine:${TAG}\n"),
        ])

        #expect(compose.services["hello"]?.image == "alpine:3.21")
    }

    @Test("Include defaults to .env beside the included file")
    func perIncludeDefaultEnv() throws {
        let (compose, _) = try load([
            .file("compose.yaml", "include:\n  - svc/compose.yaml\n"),
            .file("svc/.env", "TAG=3.19\n"),
            .file("svc/compose.yaml", "services:\n  hello:\n    image: alpine:${TAG}\n"),
        ])

        #expect(compose.services["hello"]?.image == "alpine:3.19")
    }

    @Test("Nested includes are resolved recursively")
    func nestedIncludes() throws {
        let (compose, _) = try load([
            .file("compose.yaml", "include:\n  - a/compose.yaml\n"),
            .file("a/compose.yaml", "include:\n  - ../b/compose.yaml\n"),
            .file("b/compose.yaml", "services:\n  deep:\n    image: alpine:3.20\n"),
        ])

        #expect(compose.services["deep"] != nil)
    }

    @Test("Include cycles are rejected instead of recursing forever")
    func cycleDetected() throws {
        let root = try ComposeTestHelpers.makeProjectDir([
            .file("compose.yaml", "include:\n  - other.yaml\n"),
            .file("other.yaml", "include:\n  - compose.yaml\n"),
        ])

        #expect(throws: MockerError.self) {
            _ = try ComposeFile.load(from: root.appendingPathComponent("compose.yaml").path, projectDir: root)
        }
    }

    @Test("A missing included file is an error, not a silent drop")
    func missingIncludeErrors() throws {
        let root = try ComposeTestHelpers.makeProjectDir([
            .file("compose.yaml", "include:\n  - nope.yaml\n"),
        ])

        #expect(throws: MockerError.self) {
            _ = try ComposeFile.load(from: root.appendingPathComponent("compose.yaml").path, projectDir: root)
        }
    }

    @Test("Included networks and volumes are merged too")
    func networksAndVolumesMerged() throws {
        let (compose, _) = try load([
            .file("compose.yaml", "include:\n  - svc/compose.yaml\n"),
            .file("svc/compose.yaml", """
            services:
              hello:
                image: alpine:3.20
            networks:
              backend:
            volumes:
              data:
            """),
        ])

        #expect(compose.networks["backend"] != nil)
        #expect(compose.volumes["data"] != nil)
    }

    @Test("A malformed include: is an error, not a silent drop", arguments: [
        "include: svc/compose.yaml\n",
        "include:\n  - project_directory: ./svc\n",
        "include:\n  - 42\n",
    ])
    func malformedIncludeThrows(body: String) throws {
        let root = try ComposeTestHelpers.makeProjectDir([.file("compose.yaml", body)])

        #expect(throws: MockerError.self) {
            _ = try ComposeFile.load(from: root.appendingPathComponent("compose.yaml").path, projectDir: root)
        }
    }

    @Test("An included service's relative build context anchors to the include's directory")
    func buildContextAnchoring() throws {
        let (compose, root) = try load([
            .file("compose.yaml", "include:\n  - svc/compose.yaml\n"),
            .file("svc/compose.yaml", """
            services:
              api:
                build: .
            """),
        ])

        let expected = root.appendingPathComponent("svc").standardized.path
        #expect(compose.services["api"]?.build?.context == expected)
    }

    @Test("project_directory also moves the build context")
    func buildContextHonorsProjectDirectory() throws {
        let (compose, root) = try load([
            .file("compose.yaml", """
            include:
              - path: svc/compose.yaml
                project_directory: .
            """),
            .file("svc/compose.yaml", """
            services:
              api:
                build:
                  context: ./image
                  dockerfile: Dockerfile
            """),
        ])

        let expected = root.appendingPathComponent("image").standardized.path
        #expect(compose.services["api"]?.build?.context == expected)
    }

    @Test("An included file's name: does not become the project name")
    func includedNameDoesNotLeak() throws {
        let (compose, _) = try load([
            .file("compose.yaml", "include:\n  - svc/compose.yaml\n"),
            .file("svc/compose.yaml", "name: vendor\nservices:\n  hello:\n    image: alpine:3.20\n"),
        ])

        #expect(compose.name == nil)
    }

    @Test("The parent's own name: still wins")
    func parentNameKept() throws {
        let (compose, _) = try load([
            .file("compose.yaml", "name: mine\ninclude:\n  - svc/compose.yaml\n"),
            .file("svc/compose.yaml", "name: vendor\nservices:\n  hello:\n    image: alpine:3.20\n"),
        ])

        #expect(compose.name == "mine")
    }
}
