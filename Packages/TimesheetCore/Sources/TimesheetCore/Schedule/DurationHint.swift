import Foundation

/// Parses a user-written duration such as `~2h`, `1.5h`, `1h30m`, `1h 30`, `45 min` or `90` (bare number = minutes).
public enum DurationHint {
    public static func minutes(from text: String) -> Int? {
        let pattern = /^~?\s*(?:(\d+(?:\.\d+)?)\s*h(?:ours?|rs?)?)?\s*(?:(\d+)\s*(?:m|mins?|minutes?)?)?$/
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard let match = trimmed.wholeMatch(of: pattern) else { return nil }
        let (_, hours, mins) = match.output
        guard hours != nil || mins != nil else { return nil }
        let hourMinutes = hours.flatMap { Double($0) }.map { Int(($0 * 60).rounded()) } ?? 0
        let total = hourMinutes + (mins.flatMap { Int($0) } ?? 0)
        return total > 0 ? total : nil
    }
}
