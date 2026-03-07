import Foundation

/// Formats tabular output similar to Docker CLI.
enum TableFormatter {
    /// Print a formatted table with headers and rows.
    static func print(headers: [String], rows: [[String]]) {
        guard !headers.isEmpty else { return }

        // Calculate column widths
        var widths = headers.map(\.count)
        for row in rows {
            for (i, cell) in row.enumerated() where i < widths.count {
                widths[i] = max(widths[i], cell.count)
            }
        }

        // Print header
        let headerLine = zip(headers, widths).map { header, width in
            header.uppercased().padding(toLength: width + 3, withPad: " ", startingAt: 0)
        }.joined()
        Swift.print(headerLine)

        // Print rows
        for row in rows {
            let line = zip(row, widths).map { cell, width in
                cell.padding(toLength: width + 3, withPad: " ", startingAt: 0)
            }.joined()
            Swift.print(line)
        }
    }

    /// Format a JSON-encodable value as pretty-printed JSON array (Docker inspect format).
    static func printJSONArray<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([value])
        if let json = String(data: data, encoding: .utf8) {
            Swift.print(json)
        }
    }

    /// Format a JSON-encodable value as pretty-printed JSON object.
    static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        if let json = String(data: data, encoding: .utf8) {
            Swift.print(json)
        }
    }
}
