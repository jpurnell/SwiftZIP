import Testing
import Foundation
@testable import SwiftZIP

@Suite("DOS Time Encoding")
struct DOSTimeTests {

    @Test("Known date encodes to expected DOS time and date fields")
    func knownDateEncoding() throws {
        // 2026-06-02 14:30:00 UTC
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 6, day: 2,
            hour: 14, minute: 30, second: 0
        )
        let date = try #require(components.date)
        let (time, dosDate) = DOSTime.encode(date)

        // Time: hour=14 (01110), min=30 (011110), sec/2=0 (00000) → 0x7500 is wrong, let me recalculate
        // bits: 01110_011110_00000 = 0b0111_0011_1100_0000 = 0x73C0
        // Date: year-1980=46 (0101110), month=6 (0110), day=2 (00010)
        // bits: 0101110_0110_00010 = 0b0101_1100_1100_0010 = 0x5CC2
        #expect(time == 0x73C0)
        #expect(dosDate == 0x5CC2)
    }

    @Test("DOS time round-trips within 2-second precision")
    func roundTripPrecision() throws {
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 6, day: 2,
            hour: 14, minute: 30, second: 0
        )
        let original = try #require(components.date)
        let (time, dosDate) = DOSTime.encode(original)
        let decoded = try #require(DOSTime.decode(time: time, date: dosDate))

        let diff = abs(original.timeIntervalSince(decoded))
        #expect(diff < 2.0)
    }

    @Test("Minimum DOS date: 1980-01-01 00:00:00")
    func minimumDate() throws {
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 1980, month: 1, day: 1,
            hour: 0, minute: 0, second: 0
        )
        let date = try #require(components.date)
        let (time, dosDate) = DOSTime.encode(date)
        let decoded = try #require(DOSTime.decode(time: time, date: dosDate))

        let diff = abs(date.timeIntervalSince(decoded))
        #expect(diff < 2.0)
    }

    @Test("Maximum DOS date: 2107-12-31 23:59:58")
    func maximumDate() throws {
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2107, month: 12, day: 31,
            hour: 23, minute: 59, second: 58
        )
        let date = try #require(components.date)
        let (time, dosDate) = DOSTime.encode(date)
        let decoded = try #require(DOSTime.decode(time: time, date: dosDate))

        let diff = abs(date.timeIntervalSince(decoded))
        #expect(diff < 2.0)
    }

    @Test("Zero DOS time/date decodes to nil")
    func zeroTimestamp() {
        let result = DOSTime.decode(time: 0, date: 0)
        #expect(result == nil)
    }

    @Test("Odd seconds are rounded down to 2-second boundary")
    func oddSecondsRounded() throws {
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 3, day: 15,
            hour: 10, minute: 45, second: 31
        )
        let date = try #require(components.date)
        let (time, _) = DOSTime.encode(date)
        let secondsField = time & 0x1F
        #expect(secondsField == 15) // 31/2 rounded down = 15
    }
}
