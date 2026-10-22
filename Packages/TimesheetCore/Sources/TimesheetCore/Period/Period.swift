import Foundation

public enum PeriodKind: String, CaseIterable, Sendable {
    case day, week, month

    public var displayName: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }
}

/// Day, week and month periods around an anchor date. Week start follows `calendar.firstWeekday`.
public enum Period {
    public static func range(_ kind: PeriodKind, containing anchor: Date, calendar: Calendar = .current) -> DayRange {
        guard let component = intervalComponent(kind),
              let interval = calendar.dateInterval(of: component, for: anchor) else {
            return DayRange(from: anchor, to: anchor, calendar: calendar)
        }
        // The interval's end is the first instant of the next period, so step back into the last day.
        return DayRange(from: interval.start, to: interval.end.addingTimeInterval(-1), calendar: calendar)
    }

    /// Moves the anchor by whole periods; month steps clamp (Jan 31 + 1 month = Feb 28/29).
    public static func shift(_ anchor: Date, by steps: Int, kind: PeriodKind, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component = switch kind {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        return calendar.date(byAdding: component, value: steps, to: anchor) ?? anchor
    }

    /// Day: medium date ("Oct 22, 2026"). Week: interval, medium dates ("Oct 19 – 25, 2026").
    /// Month: localized "MMMMyyyy" template ("October 2026").
    public static func label(_ kind: PeriodKind, anchor: Date, calendar: Calendar = .current,
                             locale: Locale = .current) -> String {
        switch kind {
        case .day:
            return mediumDate(anchor, calendar: calendar, locale: locale)
        case .week:
            return label(range(.week, containing: anchor, calendar: calendar), calendar: calendar, locale: locale)
        case .month:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
            return formatter.string(from: anchor)
        }
    }

    /// Custom range label: medium-date interval; a one-day range reads like a Day label.
    public static func label(_ range: DayRange, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if range.start == range.end {
            return mediumDate(range.start, calendar: calendar, locale: locale)
        }
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: range.start, to: range.end)
    }

    private static func intervalComponent(_ kind: PeriodKind) -> Calendar.Component? {
        switch kind {
        case .day: nil
        case .week: .weekOfYear
        case .month: .month
        }
    }

    private static func mediumDate(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
