import Foundation
import SwiftData

/// The compiled timesheet lines for one day; at most one record per day.
@Model
public final class CompiledDay {
    /// Always `Calendar.current.startOfDay`; unique, so inserting the same day again replaces it.
    @Attribute(.unique) public var day: Date
    public var linesData: Data
    public var compiledAt: Date

    public init(day: Date, lines: [TimesheetLine], compiledAt: Date) {
        self.day = Calendar.current.startOfDay(for: day)
        self.linesData = Self.encode(lines)
        self.compiledAt = compiledAt
    }

    /// A corrupt blob reads as no lines instead of crashing the app.
    public var lines: [TimesheetLine] {
        get { (try? JSONDecoder().decode([TimesheetLine].self, from: linesData)) ?? [] }
        set { linesData = Self.encode(newValue) }
    }

    private static func encode(_ lines: [TimesheetLine]) -> Data {
        // Encoding plain Codable values cannot fail.
        (try? JSONEncoder().encode(lines)) ?? Data("[]".utf8)
    }
}
