import Foundation

/// Encodes and decodes MS-DOS time/date format used in ZIP headers.
///
/// MS-DOS time has 2-second resolution and covers 1980-01-01 to 2107-12-31.
enum DOSTime: Sendable {

    /// Encodes a `Date` into MS-DOS time and date fields.
    ///
    /// - Parameter date: The date to encode.
    /// - Returns: A tuple of (time, date) as packed `UInt16` values.
    static func encode(_ date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )

        let year = max((comps.year ?? 1980) - 1980, 0)
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let second = comps.second ?? 0

        let time = UInt16(hour << 11) | UInt16(minute << 5) | UInt16(second / 2)
        let dosDate = UInt16(year << 9) | UInt16(month << 5) | UInt16(day)

        return (time, dosDate)
    }

    /// Decodes MS-DOS time and date fields into a `Date`.
    ///
    /// - Parameters:
    ///   - time: The packed time field from the ZIP header.
    ///   - date: The packed date field from the ZIP header.
    /// - Returns: The decoded date, or `nil` if both fields are zero.
    static func decode(time: UInt16, date: UInt16) -> Date? {
        guard time != 0 || date != 0 else { return nil }

        let second = Int(time & 0x1F) * 2
        let minute = Int((time >> 5) & 0x3F)
        let hour = Int((time >> 11) & 0x1F)
        let day = Int(date & 0x1F)
        let month = Int((date >> 5) & 0x0F)
        let year = Int((date >> 9) & 0x7F) + 1980

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )
        return components.date
    }
}
