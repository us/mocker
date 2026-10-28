import ArgumentParser
import Foundation
import MockerKit

/// Mocker has one local runtime, so the only context is the built-in `default`.
/// The commands exist so scripts that call `docker context show|ls|inspect` keep working.
struct ContextRecord: Codable, Equatable {
    struct ContextMetadata: Codable, Equatable {
        var Description: String
    }
    struct Endpoint: Codable, Equatable {
        var Host: String
        var SkipTLSVerify: Bool
    }
    struct StoragePaths: Codable, Equatable {
        var MetadataPath: String
        var TLSPath: String
    }

    var Name: String
    var Metadata: ContextMetadata
    var Endpoints: [String: Endpoint]
    var TLSMaterial: [String: [String]]
    var Storage: StoragePaths

    static let defaultName = "default"

    static func builtIn(socketPath: String = Serve.defaultSocketPath()) -> ContextRecord {
        ContextRecord(
            Name: defaultName,
            Metadata: ContextMetadata(Description: "Current mocker runtime"),
            Endpoints: ["docker": Endpoint(Host: "unix://\(socketPath)", SkipTLSVerify: false)],
            TLSMaterial: [:],
            Storage: StoragePaths(MetadataPath: "<IN MEMORY>", TLSPath: "<IN MEMORY>")
        )
    }

    var dockerEndpoint: String { Endpoints["docker"]?.Host ?? "" }
}

/// Not a `ValidationError`: that one appends the usage text and exits 64, while
/// `docker context` reports a missing context as a plain error with exit 1.
struct ContextError: Error, LocalizedError {
    var name: String
    var errorDescription: String? { "context \"\(name)\": context not found" }
}

struct ContextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "context",
        abstract: "Manage contexts",
        subcommands: [
            ContextList.self,
            ContextShow.self,
            ContextUse.self,
            ContextInspect.self,
        ]
    )
}

struct ContextList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List contexts",
        aliases: ["list"]
    )

    @Option(name: .long, help: "Format output using a custom template: 'table', 'json' or a Go template")
    var format: String?

    @Flag(name: .shortAndLong, help: "Only show context names")
    var quiet = false

    func run() async throws {
        let c = ContextRecord.builtIn()
        if quiet { print(c.Name); return }

        switch format {
        case nil, "table":
            TableFormatter.print(
                headers: ["Name", "Description", "Docker Endpoint", "Error"],
                rows: [[c.Name + " *", c.Metadata.Description, c.dockerEndpoint, ""]])
        case let format?:
            // The fields `docker context ls --format` exposes; `json` is one object per line.
            let row: [String: Any] = [
                "Name": c.Name, "Description": c.Metadata.Description,
                "DockerEndpoint": c.dockerEndpoint, "Current": true, "Error": "",
            ]
            print(try GoTemplate.render(format == "json" ? "{{json .}}" : format, object: row))
        }
    }
}

struct ContextShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Print the name of the current context"
    )

    func run() async throws {
        print(ContextRecord.defaultName)
    }
}

struct ContextUse: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "use",
        abstract: "Set the current context"
    )

    @Argument(help: "Context name")
    var name: String

    func run() async throws {
        _ = try ContextInspect.resolve([name])
        print(name)
    }
}

struct ContextInspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Display detailed information on one or more contexts"
    )

    @Argument(help: "Context names (default: the current context)")
    var contexts: [String] = []

    @Option(name: .shortAndLong, help: "Format output using a custom template")
    var format: String?

    func run() async throws {
        try InspectFormat.emitArray(try Self.resolve(contexts), format: format)
    }

    static func resolve(_ names: [String]) throws -> [ContextRecord] {
        let known = ContextRecord.builtIn()
        return try (names.isEmpty ? [known.Name] : names).map { name in
            guard name == known.Name else {
                throw ContextError(name: name)
            }
            return known
        }
    }
}
