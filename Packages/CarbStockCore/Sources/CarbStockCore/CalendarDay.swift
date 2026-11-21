import Foundation

/// A calendar day without time or time zone (spec 7.1, AC-H5).
/// Best-before dates and "today" are compared as days, so travelling across
/// time zones never shifts a remaining shelf life by one day.
public struct CalendarDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `timeZone` (the caller passes the device's local zone).
    public init(_ date: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    /// Days since 1970-01-01 (proleptic Gregorian), for arithmetic without a time zone.
    public var ordinal: Int {
        // Howard Hinnant's days_from_civil.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public init(ordinal: Int) {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yoe + era * 400 + (m <= 2 ? 1 : 0), month: m, day: d)
    }

    public func adding(days: Int) -> CalendarDay { CalendarDay(ordinal: ordinal + days) }

    /// Adds calendar months; the day is clamped to the last day of the target month (31.08. + 6 months = 28./29.02.).
    public func adding(months: Int) -> CalendarDay {
        let total = year * 12 + (month - 1) + months
        let y = Int((Double(total) / 12).rounded(.down))
        let m = total - y * 12 + 1
        let next = m == 12 ? CalendarDay(year: y + 1, month: 1, day: 1) : CalendarDay(year: y, month: m + 1, day: 1)
        let lastDay = next.adding(days: -1).day
        return CalendarDay(year: y, month: m, day: min(day, lastDay))
    }

    /// Signed number of days from `self` to `other`.
    public func days(until other: CalendarDay) -> Int { other.ordinal - ordinal }

    /// 0 = Monday … 6 = Sunday (ISO weekday, used by the weekly template).
    public var isoWeekdayIndex: Int { ((ordinal % 7) + 7 + 3) % 7 }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool { lhs.ordinal < rhs.ordinal }

    /// ISO form "yyyy-MM-dd"; this is how the persistence layer stores a day.
    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var isoString: String { description }

    public init?(isoString: String) {
        let parts = isoString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), parts[2] >= 1 else { return nil }
        let candidate = CalendarDay(year: parts[0], month: parts[1], day: parts[2])
        guard CalendarDay(ordinal: candidate.ordinal) == candidate else { return nil }
        self = candidate
    }
}
