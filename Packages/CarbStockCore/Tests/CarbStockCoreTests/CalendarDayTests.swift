import Foundation
import Testing
@testable import CarbStockCore

@Suite struct CalendarDayTests {
    @Test func ordinalRoundTrip() {
        for ordinal in stride(from: -800_000, through: 800_000, by: 997) {
            #expect(CalendarDay(ordinal: ordinal).ordinal == ordinal)
        }
        #expect(CalendarDay(year: 1970, month: 1, day: 1).ordinal == 0)
    }

    @Test func addingMonthsClampsToMonthEnd() {
        #expect(CalendarDay(year: 2026, month: 8, day: 31).adding(months: 6) == CalendarDay(year: 2027, month: 2, day: 28))
        #expect(CalendarDay(year: 2027, month: 8, day: 31).adding(months: 6) == CalendarDay(year: 2028, month: 2, day: 29))
        #expect(CalendarDay(year: 2026, month: 1, day: 15).adding(months: -2) == CalendarDay(year: 2025, month: 11, day: 15))
    }

    @Test func weekdayIndexIsISO() {
        #expect(CalendarDay(year: 2026, month: 11, day: 23).isoWeekdayIndex == 0) // Monday
        #expect(CalendarDay(year: 2026, month: 11, day: 22).isoWeekdayIndex == 6) // Sunday
    }

    /// AC-H5: the same instant is a different local day in different zones, but a stored
    /// CalendarDay best-before date never moves.
    @Test func dayFromDateUsesGivenTimeZone() {
        let instant = Date(timeIntervalSince1970: 1_795_300_000) // 2026-11-21 ~ 22:26 UTC
        let berlin = CalendarDay(instant, in: TimeZone(identifier: "Europe/Berlin")!)
        let tokyo = CalendarDay(instant, in: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(berlin == CalendarDay(year: 2026, month: 11, day: 21))
        #expect(tokyo == CalendarDay(year: 2026, month: 11, day: 22))
    }

    @Test func isoStringRoundTrip() {
        let day = CalendarDay(year: 2027, month: 3, day: 1)
        #expect(day.isoString == "2027-03-01")
        #expect(CalendarDay(isoString: "2027-03-01") == day)
        #expect(CalendarDay(isoString: "2027-02-30") == nil)
        #expect(CalendarDay(isoString: "kaputt") == nil)
    }
}
