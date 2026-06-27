import Foundation

/// Minimal Go `text/template` field-path evaluator for `inspect --format`.
///
/// Why this exists
/// ---------------
/// `mocker inspect` mirrors `docker inspect`, and real-world callers drive it with
/// `-f '{{.State.Running}}'` style templates (dev stands, CI health gates, e.g.
/// `docker inspect -f '{{.State.Running}}' c | grep -q true`). Docker evaluates the
/// template and prints a bare scalar. Until now `--format` was parsed but ignored and
/// the full JSON dumped, breaking every such caller.
///
/// Scope (intentionally small, and fails loudly outside it)
/// --------------------------------------------------------
/// We support the `{{ .Dotted.Path }}` field-access subset that container/image
/// inspect callers actually use — not the full Go template language (no `if`,
/// `range`, pipelines, or functions). A path is resolved against the record's
/// JSON object (which is already Docker-shaped: `Id`, `State.Running`, `Config.Image`,
/// `NetworkSettings.IPAddress`, …); an unknown or null path renders empty (Docker
/// prints `<no value>`, but empty is safe for the boolean/string checks these
/// templates feed and avoids a surprising literal in scripted output).
///
/// Any `{{ … }}` block that is NOT a supported field access (`{{if}}`, `{{range}}`,
/// `{{json .X}}`, `{{index …}}`, a bare `{{.}}`, …) is rejected with a thrown
/// `GoTemplateError`, not emitted as literal text. A silently-unevaluated template
/// would feed false data to the `grep`/`jq` pipelines these outputs drive, so the
/// unsupported case must surface as a nonzero exit rather than wrong output.

/// Raised when an `inspect --format` template uses a construct outside the supported
/// `{{ .Dotted.Path }}` field-access subset.
enum GoTemplateError: Error, LocalizedError, CustomStringConvertible {
    case unsupportedAction(String)

    var description: String {
        switch self {
        case .unsupportedAction(let block):
            return "inspect --format: unsupported template action \(block); only field access "
                + "like {{ .State.Running }} is supported (no if/range/pipelines/functions)"
        }
    }

    // ArgumentParser prints thrown errors via `localizedDescription`, which only honors
    // LocalizedError — without this the helpful message above is replaced by a generic
    // "The operation couldn't be completed" string (matches MockerError's pattern).
    var errorDescription: String? { description }
}

enum GoTemplate {
    /// Render `template` against one inspect record, supplied as its encoded JSON object.
    ///
    /// - Parameters:
    ///   - template: A Go template string containing `{{ .Path }}` field tokens.
    ///   - object: The record's JSON, decoded to a dictionary (one element of the
    ///     inspect array).
    /// - Returns: The template with every field token replaced by its resolved value.
    /// - Throws: `GoTemplateError.unsupportedAction` if a `{{ … }}` block is not a
    ///   supported field access.
    static func render(_ template: String, object: [String: Any]) throws -> String {
        let full = NSRange(template.startIndex..., in: template)

        // Single left-to-right pass: copy the literal text between `{{…}}` blocks verbatim
        // and splice each field path's resolved value in at its ORIGINAL position.
        // Substituting by range (never by a global string replacement on a mutated buffer)
        // means a resolved value that itself contains `{{…}}` is emitted as literal output
        // and can never re-trigger substitution, and repeated tokens cannot contaminate
        // each other's output (the earlier `replacingOccurrences` approach rendered
        // `{{.A}} {{.B}}` with `A == "{{.B}}"` as `valueB valueB`, not `{{.B}} valueB`).
        var result = ""
        var cursor = template.startIndex
        for match in actionRegex.matches(in: template, range: full) {
            guard let blockRange = Range(match.range, in: template) else { continue }
            let block = String(template[blockRange])
            let path = try fieldPath(of: block)
            result += String(template[cursor..<blockRange.lowerBound])
            result += resolveValue(path: path, in: object)
            cursor = blockRange.upperBound
        }
        result += String(template[cursor...])
        return result
    }

    /// Extract the dotted field path from one `{{…}}` block, or throw if the whole block is
    /// not a supported `{{ .Path }}` field access.
    private static func fieldPath(of block: String) throws -> [String] {
        let whole = NSRange(block.startIndex..., in: block)
        guard let match = fieldRegex.firstMatch(in: block, range: whole),
              match.range.location == whole.location, match.range.length == whole.length,
              let pathRange = Range(match.range(at: 1), in: block) else {
            throw GoTemplateError.unsupportedAction(block)
        }
        return block[pathRange].split(separator: ".").map(String.init)
    }

    // Patterns are constant and valid, so compile once at first access. `[\s\S]` (not `.`)
    // lets a `{{ … }}` block span newlines; the pattern is linear, so no ReDoS.
    private static let actionRegex = try! NSRegularExpression(pattern: #"\{\{[\s\S]*?\}\}"#)
    /// A supported `{{ .Dotted.Path }}` field access: optional surrounding whitespace, a
    /// leading dot, then a dotted identifier path.
    private static let fieldRegex = try! NSRegularExpression(pattern: #"\{\{\s*\.([A-Za-z0-9_.]+)\s*\}\}"#)

    // MARK: - Path resolution

    /// Walk a dotted path through nested dictionaries, rendering the leaf as a scalar.
    private static func resolveValue(path: [String], in object: [String: Any]) -> String {
        var current: Any = object
        for key in path {
            guard let dict = current as? [String: Any], let next = dict[key] else {
                return ""
            }
            current = next
        }
        return scalar(current)
    }

    /// Render a JSON leaf the way Go's template prints it: bare `true`/`false`,
    /// integers without a decimal point, strings verbatim; containers/null → empty.
    private static func scalar(_ value: Any) -> String {
        if value is NSNull { return "" }
        // Both `JSONSerialization` output and bridged Swift `Bool`/`Int` arrive as
        // NSNumber here; the CFBoolean type id is the ONLY reliable bool discriminator.
        // Check it first so an integer field whose value is 0/1 (e.g. `{{.State.Pid}}`)
        // doesn't get mis-rendered as `false`/`true`.
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            if number.doubleValue == Double(number.int64Value) {
                return String(number.int64Value)
            }
            return number.stringValue
        }
        if let string = value as? String {
            return string
        }
        return ""  // arrays / objects / unknown render empty, like a bare {{.Field}} on a map
    }
}
