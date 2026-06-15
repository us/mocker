import ArgumentParser
import MockerKit
import Foundation

struct History: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the history of an image"
    )

    @Argument(help: "Image name or ID")
    var image: String

    @Option(name: .long, help: "Format output using a custom template")
    var format: String?

    @Flag(name: [.customShort("H"), .long], inversion: .prefixedNo, help: "Print sizes and dates in human readable format")
    var human = true

    @Flag(name: .customLong("no-trunc"), help: "Don't truncate output")
    var noTrunc = false

    @Flag(name: .shortAndLong, help: "Only show image IDs")
    var quiet = false

    @Option(name: .long, help: "Set platform to show history for")
    var platform: String?

    func run() async throws {
        let config = MockerConfig()
        let manager = try ImageManager(config: config)
        let info = try await manager.inspect(image, platform: platform)

        let shortID = String(info.id.prefix(12))
        let sizeString = ByteCountFormatter.string(fromByteCount: info.size, countStyle: .file)
        let createdAgo = info.created.map { RelativeDate.humanRelative($0) } ?? "N/A"

        if quiet {
            print(noTrunc ? info.id : shortID)
            return
        }

        // Simplified history — show single layer since we don't have full layer info
        let headers = ["IMAGE", "CREATED", "CREATED BY", "SIZE", "COMMENT"]
        let rows = [[
            noTrunc ? info.id : shortID,
            createdAgo,
            "",
            sizeString,
            "",
        ]]
        TableFormatter.print(headers: headers, rows: rows)
    }
}

/// Parses OCI `created` timestamps and renders them as human-relative dates.
///
/// `ISO8601DateFormatter` only understands millisecond fractions, so OCI configs
/// carrying nanosecond precision (e.g. `2024-11-19T17:01:02.000000000Z`) fail to
/// parse and previously fell back to the raw string. This helper tolerates variable
/// fractional precision, including 9-digit nanoseconds.
enum RelativeDate {
    /// Parses an RFC3339 / RFC3339Nano timestamp into a `Date`, or `nil` if unparseable.
    static func parse(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }

        // Last resort: strip an over-precise fractional component and retry.
        if let stripped = stripFractionalSeconds(string) {
            return plain.date(from: stripped)
        }
        return nil
    }

    /// Renders the timestamp as an abbreviated relative date, falling back to the
    /// raw string only when it cannot be parsed.
    static func humanRelative(_ string: String, relativeTo now: Date = Date()) -> String {
        guard let date = parse(string) else { return string }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Removes the fractional-seconds component, preserving the timezone designator.
    private static func stripFractionalSeconds(_ string: String) -> String? {
        guard let dot = string.firstIndex(of: ".") else { return nil }
        let afterDot = string[string.index(after: dot)...]
        let timezone = afterDot.firstIndex { !$0.isNumber }.map { String(afterDot[$0...]) } ?? ""
        return String(string[string.startIndex..<dot]) + timezone
    }
}
