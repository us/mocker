import Foundation

/// Parses OCI `created` timestamps and renders them as human-relative dates.
///
/// `ISO8601DateFormatter` only understands millisecond fractions, so OCI configs
/// carrying nanosecond precision (e.g. `2024-11-19T17:01:02.000000000Z`) fail to
/// parse and previously fell back to the raw string. This helper tolerates variable
/// fractional precision, including 9-digit nanoseconds.
public enum RelativeDate {
    /// Parses an RFC3339 / RFC3339Nano timestamp into a `Date`, or `nil` if unparseable.
    public static func parse(_ string: String) -> Date? {
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
    public static func humanRelative(_ string: String, relativeTo now: Date = Date()) -> String {
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
