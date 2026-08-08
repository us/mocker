import Testing
import Foundation
@testable import MockerKit

@Suite("Compose project name + service validation")
struct ComposeProjectNameTests {
    @Test("Top-level name: is parsed")
    func parsesTopLevelName() throws {
        let compose = try ComposeFile.parse("""
        name: myproj
        services:
          web:
            image: nginx:latest
        """)

        #expect(compose.name == "myproj")
    }

    @Test("Explicit -p wins over every other source")
    func explicitWins() throws {
        let root = try ComposeTestHelpers.makeProjectDir([
            .file(".env", "COMPOSE_PROJECT_NAME=fromdotenv\n"),
        ])

        let resolved = ComposeFile.resolveProjectName(
            explicit: "flag",
            composeFileName: "fromfile",
            projectDir: root,
            environment: ["COMPOSE_PROJECT_NAME": "fromenv"]
        )

        #expect(resolved == "flag")
    }

    @Test("Environment beats .env, compose name and directory")
    func environmentBeatsDotEnv() throws {
        let root = try ComposeTestHelpers.makeProjectDir([
            .file(".env", "COMPOSE_PROJECT_NAME=fromdotenv\n"),
        ])

        let resolved = ComposeFile.resolveProjectName(
            explicit: nil,
            composeFileName: "fromfile",
            projectDir: root,
            environment: ["COMPOSE_PROJECT_NAME": "fromenv"]
        )

        #expect(resolved == "fromenv")
    }

    @Test(".env beats the compose file's name: and the directory")
    func dotEnvBeatsComposeName() throws {
        let root = try ComposeTestHelpers.makeProjectDir([
            .file(".env", "COMPOSE_PROJECT_NAME=fromdotenv\n"),
        ])

        let resolved = ComposeFile.resolveProjectName(
            explicit: nil,
            composeFileName: "fromfile",
            projectDir: root,
            environment: [:]
        )

        #expect(resolved == "fromdotenv")
    }

    @Test("Compose file name: beats the directory basename")
    func composeNameBeatsDirectory() throws {
        let root = try ComposeTestHelpers.makeProjectDir()

        let resolved = ComposeFile.resolveProjectName(
            explicit: nil,
            composeFileName: "fromfile",
            projectDir: root,
            environment: [:]
        )

        #expect(resolved == "fromfile")
    }

    @Test("Directory basename is the last resort")
    func directoryFallback() throws {
        let root = try ComposeTestHelpers.makeProjectDir()
            .appendingPathComponent("My Project")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let resolved = ComposeFile.resolveProjectName(
            explicit: nil,
            composeFileName: nil,
            projectDir: root,
            environment: [:]
        )

        #expect(resolved == "my-project")
    }

    @Test("Resolved names are normalized to Compose's character set", arguments: [
        ("Feature.FOO", "feature-foo"),
        ("-leading", "leading"),
        ("UPPER_case-1", "upper_case-1"),
    ])
    func normalization(input: String, expected: String) throws {
        #expect(ComposeFile.normalizeProjectName(input) == expected)
    }

    @Test("A name with nothing usable falls back to a placeholder")
    func normalizationEmpty() throws {
        #expect(ComposeFile.normalizeProjectName("...") == "default")
    }

    @Test("Unknown service names are rejected")
    func validateUnknownService() throws {
        let compose = try ComposeFile.parse("services:\n  web:\n    image: nginx\n")

        #expect(throws: MockerError.self) {
            try compose.validateServiceNames(["ghost"])
        }
        #expect(throws: Never.self) {
            try compose.validateServiceNames(["web"])
        }
    }

    @Test("Filtering keeps the project name")
    func filteringKeepsName() throws {
        let compose = try ComposeFile.parse("""
        name: keepme
        services:
          web:
            image: nginx
          db:
            image: postgres
        """)

        #expect(compose.filtering(services: ["web"]).name == "keepme")
    }

    @Test("Later -f file's name: wins on merge")
    func mergeNamePrecedence() throws {
        let base = try ComposeFile.parse("name: first\nservices:\n  web:\n    image: nginx\n")
        let overlay = try ComposeFile.parse("name: second\nservices: {}\n")
        let noName = try ComposeFile.parse("services: {}\n")

        #expect(ComposeFile.merge([base, overlay]).name == "second")
        #expect(ComposeFile.merge([base, noName]).name == "first")
    }
}
