import Foundation

/// A calendar date as "yyyy-MM-dd" (Gregorian). Days are stored and matched by this key, not by an
/// instant, so a day's data is still found after the Mac's time zone changes.
public enum DayKey {
    public static func string(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"),
                      c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
