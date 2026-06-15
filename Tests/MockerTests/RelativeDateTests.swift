import Testing
import Foundation
@testable import Mocker

@Suite("RelativeDate Tests")
struct RelativeDateTests {

    let nanoTimestamp = "2024-11-19T17:01:02.000000000Z"

    @Test("parse handles 9-digit nanosecond fractional seconds")
    func parsesNanosecondTimestamp() throws {
        let date = try #require(RelativeDate.parse(nanoTimestamp))
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let expected = try #require(plain.date(from: "2024-11-19T17:01:02Z"))
        #expect(date == expected)
    }

    @Test("parse handles millisecond fractional seconds")
    func parsesMillisecondTimestamp() throws {
        let date = RelativeDate.parse("2024-11-19T17:01:02.123Z")
        #expect(date != nil)
    }

    @Test("parse handles plain RFC3339 without fractional seconds")
    func parsesPlainTimestamp() throws {
        let date = RelativeDate.parse("2024-11-19T17:01:02Z")
        #expect(date != nil)
    }

    @Test("humanRelative does not return the raw nanosecond string")
    func humanRelativeNotRawForNanoseconds() {
        let result = RelativeDate.humanRelative(nanoTimestamp)
        #expect(result != nanoTimestamp)
    }

    @Test("humanRelative falls back to raw string for unparseable input")
    func humanRelativeFallsBackForGarbage() {
        let garbage = "not-a-timestamp"
        #expect(RelativeDate.humanRelative(garbage) == garbage)
    }
}
