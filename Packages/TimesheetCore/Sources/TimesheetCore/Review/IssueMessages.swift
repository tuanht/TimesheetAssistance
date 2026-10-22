import Foundation

/// Readable text for validation issues, shown on the row they belong to.
public enum IssueMessages {
    public static func message(for issue: LineIssue, lines: [TimesheetLine], settings: AppSettings) -> String {
        let line = lines.first { $0.id == issue.lineId }
        let hours = settings.workingHours
        switch issue.kind {
        case .missingLine:
            return "This entry has no line."
        case .endNotAfterStart:
            return "End is not after start."
        case .outsideWorkingHours:
            return "Outside working hours (\(hours.start.hhmm)–\(hours.end.hhmm))."
        case .inLunch:
            return "Overlaps lunch (\(hours.lunchStart.hhmm)–\(hours.lunchEnd.hhmm))."
        case .overlaps(let otherId):
            guard let other = lines.first(where: { $0.id == otherId }) else { return "Overlaps another line." }
            return "Overlaps the line at \(other.start.hhmm)–\(other.end.hhmm)."
        case .unknownActivityType:
            return unlisted("Activity type", line?.activityType ?? "")
        case .unknownClassification:
            return unlisted("Classification", line?.classification ?? "")
        case .invalidTicket:
            return "Ticket “\(line?.ticket ?? "")” doesn’t match the ticket pattern."
        case .descriptionTooLong:
            return "Description is longer than \(settings.template.maxDescriptionLength ?? 0) characters."
        }
    }

    /// Messages for one row's issues, in validator order.
    public static func rowMessages(
        for lineId: UUID, issues: [LineIssue], lines: [TimesheetLine], settings: AppSettings
    ) -> [String] {
        issues.filter { $0.lineId == lineId }.map { message(for: $0, lines: lines, settings: settings) }
    }

    /// Entries without a line have no row to show a warning on, so they get one summary.
    public static func missingLinesSummary(_ issues: [LineIssue]) -> String? {
        let count = issues.filter { $0.kind == .missingLine }.count
        switch count {
        case 0: return nil
        case 1: return "1 entry has no line."
        default: return "\(count) entries have no line."
        }
    }

    private static func unlisted(_ field: String, _ value: String) -> String {
        value.isEmpty ? "\(field) is empty." : "\(field) “\(value)” isn’t in the list."
    }
}
