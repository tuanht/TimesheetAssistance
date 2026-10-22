import Foundation
import Testing
@testable import TimesheetCore

struct IssueMessagesTests {
    let settings = AppSettings.default

    func line(_ start: ClockTime, _ end: ClockTime, activity: String = "Development",
              classification: String = "Billable", ticket: String? = nil) -> TimesheetLine {
        TimesheetLine(entryId: UUID(), start: start, end: end, description: "Work", ticket: ticket,
                      activityType: activity, classification: classification)
    }

    @Test func eachKindHasAMessage() {
        let other = line(ClockTime(10, 0), ClockTime(11, 0))
        let target = line(ClockTime(10, 30), ClockTime(10, 0), activity: "Dev", classification: "", ticket: "x")
        var withMax = settings
        withMax.template.maxDescriptionLength = 3
        let lines = [other, target]
        let cases: [(LineIssue.Kind, String)] = [
            (.endNotAfterStart, "End is not after start."),
            (.outsideWorkingHours, "Outside working hours (09:00–17:30)."),
            (.inLunch, "Overlaps lunch (12:00–13:00)."),
            (.overlaps(other.id), "Overlaps the line at 10:00–11:00."),
            (.unknownActivityType, "Activity type “Dev” isn’t in the list."),
            (.unknownClassification, "Classification is empty."),
            (.invalidTicket, "Ticket “x” doesn’t match the ticket pattern."),
            (.descriptionTooLong, "Description is longer than 3 characters."),
            (.orphanLine, "Its entry was deleted."),
            (.emptyDescription, "Description is empty."),
        ]
        for (kind, expected) in cases {
            let issue = LineIssue(lineId: target.id, entryId: target.entryId, kind: kind)
            #expect(IssueMessages.message(for: issue, lines: lines, settings: withMax) == expected)
        }
    }

    @Test func overlapWithVanishedLineStillReads() {
        let target = line(ClockTime(9, 0), ClockTime(10, 0))
        let issue = LineIssue(lineId: target.id, entryId: target.entryId, kind: .overlaps(UUID()))
        #expect(IssueMessages.message(for: issue, lines: [target], settings: settings) == "Overlaps another line.")
    }

    @Test func rowMessagesKeepOnlyThatRowsIssues() {
        let a = line(ClockTime(9, 0), ClockTime(10, 0), activity: "Dev")
        let b = line(ClockTime(10, 0), ClockTime(11, 0), classification: "X")
        let issues = LineValidator.validate([a, b], entryIds: [a.entryId, b.entryId], settings: settings)
        #expect(IssueMessages.rowMessages(for: a.id, issues: issues, lines: [a, b], settings: settings)
            == ["Activity type “Dev” isn’t in the list."])
        #expect(IssueMessages.rowMessages(for: b.id, issues: issues, lines: [a, b], settings: settings)
            == ["Classification “X” isn’t in the list."])
    }

    @Test func missingLinesSummary() {
        let issues = [
            LineIssue(lineId: nil, entryId: UUID(), kind: .missingLine),
            LineIssue(lineId: nil, entryId: UUID(), kind: .missingLine),
        ]
        #expect(IssueMessages.missingLinesSummary(issues) == "2 entries have no line.")
        #expect(IssueMessages.missingLinesSummary(Array(issues.prefix(1))) == "1 entry has no line.")
        #expect(IssueMessages.missingLinesSummary([]) == nil)
    }
}
