import Foundation

/// Shared `inspect --format` output path for the top-level `inspect` command and the
/// dedicated `container inspect` / `image inspect` subcommands.
///
/// When `format` is nil -- or the literal `json`, which Docker documents as a special
/// `--format` value, not a template -- the records print as the existing JSON (a single
/// object for `emitOne`, an array for `emitArray`). Otherwise each record is rendered
/// through `GoTemplate`, one line per record, the way `docker inspect -f` does.
enum InspectFormat {
    /// Emit a single inspect record. Slashes are never escaped, matching Docker's
    /// `inspect` JSON (`docker.io/library/...`, not `docker.io\/library\/...`).
    static func emitOne<T: Encodable>(_ value: T, format: String?) throws {
        guard let format, format != "json" else {
            try TableFormatter.printJSONArray(value, escapeSlashes: false)
            return
        }
        print(try GoTemplate.render(format, object: try jsonObject(value)))
    }

    /// Emit a collection of inspect records (one rendered line each under `--format`).
    static func emitArray<T: Encodable>(_ values: [T], format: String?) throws {
        guard let format, format != "json" else {
            try TableFormatter.printJSONArray(values, escapeSlashes: false)
            return
        }
        for value in values {
            print(try GoTemplate.render(format, object: try jsonObject(value)))
        }
    }

    /// Encode `value` to JSON and decode it back to a dictionary for path resolution.
    /// Going through JSON guarantees the template sees the exact keys mocker emits.
    private static func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
