import Foundation
import Testing
@testable import TimesheetCore

struct PeriodTests {
    private func calendar(firstWeekday: Int = 2) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        cal.locale = Locale(identifier: "en_US")
        cal.firstWeekday = firstWeekday
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    @Test func dayRangeIsOneDay() {
        let cal = calendar()
        let range = Period.range(.day, containing: date(2026, 10, 22, hour: 15, in: cal), calendar: cal)
        #expect(range.keys(calendar: cal) == ["2026-10-22"])
    }

    @Test func weekMondayFirst() {
        let cal = calendar(firstWeekday: 2)
        let keys = Period.range(.week, containing: date(2026, 10, 22, in: cal), calendar: cal).keys(calendar: cal)
        #expect(keys.count == 7)
        #expect(keys.first == "2026-10-19")
        #expect(keys.last == "2026-10-25")
    }

    @Test func weekSundayFirst() {
        let cal = calendar(firstWeekday: 1)
        let keys = Period.range(.week, containing: date(2026, 10, 22, in: cal), calendar: cal).keys(calendar: cal)
        #expect(keys.first == "2026-10-18")
        #expect(keys.last == "2026-10-24")
    }

    @Test func weekCrossesYear() {
        let cal = calendar(firstWeekday: 2)
        let keys = Period.range(.week, containing: date(2026, 12, 31, in: cal), calendar: cal).keys(calendar: cal)
        #expect(keys.first == "2026-12-28")
        #expect(keys.last == "2027-01-03")
    }

    @Test func monthLeapFebruary() {
        let cal = calendar()
        let keys = Period.range(.month, containing: date(2028, 2, 10, in: cal), calendar: cal).keys(calendar: cal)
        #expect(keys.count == 29)
        #expect(keys.first == "2028-02-01")
        #expect(keys.last == "2028-02-29")
    }

    @Test func rangeNormalizesReversedDates() {
        let cal = calendar()
        let range = DayRange(from: date(2026, 10, 25, in: cal), to: date(2026, 10, 20, in: cal), calendar: cal)
        #expect(range.keys(calendar: cal) == ["2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23",
                                              "2026-10-24", "2026-10-25"])
    }

    @Test func shiftMonthClamps() {
        let cal = calendar()
        let shifted = Period.shift(date(2028, 1, 31, in: cal), by: 1, kind: .month, calendar: cal)
        #expect(DayKey.string(for: shifted, timeZone: cal.timeZone) == "2028-02-29")
    }

    @Test func shiftWeekBackwards() {
        let cal = calendar()
        let shifted = Period.shift(date(2026, 10, 22, in: cal), by: -1, kind: .week, calendar: cal)
        #expect(DayKey.string(for: shifted, timeZone: cal.timeZone) == "2026-10-15")
    }

    @Test func monthLabel() {
        let cal = calendar()
        #expect(Period.label(.month, anchor: date(2026, 10, 22, in: cal), calendar: cal,
                             locale: Locale(identifier: "en_US")) == "October 2026")
    }

    @Test func weekLabelMentionsBothEnds() {
        let cal = calendar()
        let label = Period.label(.week, anchor: date(2026, 10, 22, in: cal), calendar: cal,
                                 locale: Locale(identifier: "en_US"))
        #expect(label.contains("Oct"))
        #expect(label.contains("19"))
        #expect(label.contains("25"))
    }
}
