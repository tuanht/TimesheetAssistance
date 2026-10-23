import Foundation

/// Clock times an entry's own text states, such as `9:30`, `14:00`, `2pm` or `9:15 AM`.
/// The compiler keeps a model's fixed slot only when its start is one of these, because
/// models invent meeting times for entries that only state a duration.
/// `9.30` and `14h30` are not read, as they clash with durations (`1h30`) and versions.
public enum ClockMention {
    // A digit or ':' on either side blocks a match, so `112:30` and `1:2:3` are not times.
    // Groups: 1 hour, 2 minutes, 3 am/pm after H:mm; 4 hour, 5 am/pm for the bare-hour form.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<![\d:])(?:(\d{1,2}):(\d{2})(?![\d:])(?:\s?([ap]m)(?![a-z]))?|(\d{1,2})\s?([ap]m)(?![a-z]))"#,
        options: [.caseInsensitive])

    public static func times(in text: String) -> Set<ClockTime> {
        let ns = text as NSString
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return Set(matches.compactMap { match in
            func group(_ i: Int) -> String? {
                let r = match.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            if let h = group(1).flatMap(Int.init), let m = group(2).flatMap(Int.init) {
                // "13:00 pm" is a 24-hour time with a stray suffix, so read it as H:mm.
                return time(hour: h, minute: m, meridiem: (13..<24).contains(h) ? nil : group(3))
            }
            return group(4).flatMap(Int.init).flatMap { time(hour: $0, minute: 0, meridiem: group(5)) }
        })
    }

    /// 24-hour without am/pm; with it, hours run 1–12 and 12am is midnight.
    private static func time(hour: Int, minute: Int, meridiem: String?) -> ClockTime? {
        guard (0..<60).contains(minute) else { return nil }
        guard let meridiem else {
            return (0..<24).contains(hour) ? ClockTime(hour, minute) : nil
        }
        guard (1...12).contains(hour) else { return nil }
        let pm = meridiem.lowercased() == "pm"
        return ClockTime(hour % 12 + (pm ? 12 : 0), minute)
    }
}
