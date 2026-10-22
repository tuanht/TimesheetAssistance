import Foundation

public struct LineIssue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case missingLine
        case endNotAfterStart
        case outsideWorkingHours
        case inLunch
        case overlaps(UUID)
        case unknownActivityType
        case unknownClassification
        case invalidTicket
        case descriptionTooLong
    }

    public var lineId: UUID?
    public var entryId: UUID?
    public var kind: Kind

    public init(lineId: UUID?, entryId: UUID?, kind: Kind) {
        self.lineId = lineId
        self.entryId = entryId
        self.kind = kind
    }
}

/// Flags problems for the user to fix; never modifies lines.
public enum LineValidator {
    /// Issues ordered: missing lines (in `entryIds` order), then per line in input order.
    public static func validate(_ lines: [TimesheetLine], entryIds: [UUID], settings: AppSettings) -> [LineIssue] {
        let covered = Set(lines.map(\.entryId))
        var issues = entryIds
            .filter { !covered.contains($0) }
            .map { LineIssue(lineId: nil, entryId: $0, kind: .missingLine) }

        let hours = settings.workingHours
        let hasLunch = hours.lunchStart < hours.lunchEnd
        let ticketRegex = try? Regex(settings.template.ticketPattern)

        for line in lines {
            func flag(_ kind: LineIssue.Kind) {
                issues.append(LineIssue(lineId: line.id, entryId: line.entryId, kind: kind))
            }
            if line.end <= line.start { flag(.endNotAfterStart) }
            if line.start < hours.start || line.end > hours.end { flag(.outsideWorkingHours) }
            if hasLunch, intersects(line.start, line.end, hours.lunchStart, hours.lunchEnd) { flag(.inLunch) }
            for other in lines where other.id != line.id
                && intersects(line.start, line.end, other.start, other.end) {
                flag(.overlaps(other.id))
            }
            if !settings.activityTypes.contains(line.activityType) { flag(.unknownActivityType) }
            if !settings.classifications.contains(line.classification) { flag(.unknownClassification) }
            if let ticket = line.ticket, !ticket.isEmpty, let ticketRegex,
               (try? ticketRegex.wholeMatch(in: ticket)) == nil {
                flag(.invalidTicket)
            }
            if let max = settings.template.maxDescriptionLength, line.description.count > max {
                flag(.descriptionTooLong)
            }
        }
        return issues
    }

    /// Sum of line durations; inverted lines count as zero.
    public static func totalMinutes(_ lines: [TimesheetLine]) -> Int {
        lines.reduce(0) { $0 + max(0, $1.end.minutes - $1.start.minutes) }
    }

    /// Working span minus the part of lunch that falls inside it.
    public static func workingMinutes(_ hours: WorkingHours) -> Int {
        let span = max(0, hours.end.minutes - hours.start.minutes)
        let lunch = max(0, min(hours.end, hours.lunchEnd).minutes - max(hours.start, hours.lunchStart).minutes)
        return span - lunch
    }

    /// Half-open intervals; touching ends do not intersect.
    private static func intersects(_ aStart: ClockTime, _ aEnd: ClockTime, _ bStart: ClockTime, _ bEnd: ClockTime) -> Bool {
        aStart < bEnd && bStart < aEnd
    }
}
