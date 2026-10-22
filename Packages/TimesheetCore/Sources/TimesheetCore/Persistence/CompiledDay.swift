import Foundation
import SwiftData

/// The compiled timesheet lines for one day; at most one record per day.
@Model
public final class CompiledDay {
    /// The calendar date from `DayKey`; unique, so inserting the same day again replaces it.
    @Attribute(.unique) public var dayKey: String
    public var linesData: Data
    public var compiledAt: Date

    /// `day` is read as a calendar date in `timeZone`.
    public init(day: Date, lines: [TimesheetLine], compiledAt: Date, timeZone: TimeZone = .current) {
        self.dayKey = DayKey.string(for: day, timeZone: timeZone)
        self.linesData = Self.encode(lines)
        self.compiledAt = compiledAt
    }

    /// Decoded line by line: a line that can't be read is dropped and the rest are kept.
    /// A corrupt blob reads as no lines instead of crashing the app.
    public var lines: [TimesheetLine] {
        get {
            guard let items = try? JSONDecoder().decode([LossyLine].self, from: linesData) else { return [] }
            return items.compactMap(\.line)
        }
        set { linesData = Self.encode(newValue) }
    }

    private static func encode(_ lines: [TimesheetLine]) -> Data {
        // Encoding plain Codable values cannot fail.
        (try? JSONEncoder().encode(lines)) ?? Data("[]".utf8)
    }
}

/// One array element that decodes to `nil` instead of failing the whole array.
private struct LossyLine: Decodable {
    let line: TimesheetLine?

    init(from decoder: Decoder) throws {
        line = try? TimesheetLine(from: decoder)
    }
}
