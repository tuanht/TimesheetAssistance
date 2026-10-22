import Foundation
import TimesheetCore

/// One day of a compile range: its entries, its lines (saved as that day's `CompiledDay`) and their issues.
struct DayResult {
    let day: Date
    var entryIds: [UUID]
    var lines: [TimesheetLine]
    var issues: [LineIssue]
    /// True once the day has a saved result, so compiling again asks before replacing it.
    var hasSaved: Bool
}

/// A table row: a line with the day it belongs to.
struct DatedLine: Identifiable {
    let day: Date
    let line: TimesheetLine
    var id: UUID { line.id }
}
