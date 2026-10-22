import Foundation

/// An inclusive run of whole days, held as start-of-day dates in the calendar it was built with.
public struct DayRange: Equatable, Sendable {
    public let start: Date   // start of day in `calendar`
    public let end: Date     // start of the last day (inclusive)

    /// Swaps the dates if `to` is before `from`.
    public init(from: Date, to: Date, calendar: Calendar = .current) {
        let a = calendar.startOfDay(for: from)
        let b = calendar.startOfDay(for: to)
        start = min(a, b)
        end = max(a, b)
    }

    /// Every day in the range, oldest first, as start-of-day dates.
    public func days(calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var day = start
        while day <= end {
            result.append(day)
            // Step by calendar day, not 24 h, so DST changes don't skip or repeat a day.
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return result
    }

    /// `DayKey.string(for:timeZone: calendar.timeZone)` for each day.
    public func keys(calendar: Calendar = .current) -> [String] {
        days(calendar: calendar).map { DayKey.string(for: $0, timeZone: calendar.timeZone) }
    }
}
