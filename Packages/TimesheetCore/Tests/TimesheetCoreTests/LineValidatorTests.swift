import Foundation
import Testing
@testable import TimesheetCore

struct LineValidatorTests {
    private let entry = UUID()

    private func line(
        _ start: String, _ end: String, entry: UUID? = nil, description: String = "Work",
        ticket: String? = "RSF-1", activity: String = "Development", classification: String = "Billable"
    ) -> TimesheetLine {
        TimesheetLine(
            entryId: entry ?? self.entry, start: ClockTime(start)!, end: ClockTime(end)!,
            description: description, ticket: ticket, activityType: activity,
            classification: classification)
    }

    private func validate(
        _ lines: [TimesheetLine], entryIds: [UUID]? = nil, settings: AppSettings = .default
    ) -> [LineIssue] {
        LineValidator.validate(lines, entryIds: entryIds ?? [entry], settings: settings)
    }

    @Test func entryWithoutLineIsMissing() {
        let other = UUID()
        let issues = validate([line("09:00", "10:00")], entryIds: [entry, other])
        #expect(issues == [LineIssue(lineId: nil, entryId: other, kind: .missingLine)])
    }

    @Test func lineForDeletedEntryIsOrphan() {
        let deleted = UUID()
        let kept = line("09:00", "10:00")
        let orphan = line("10:00", "11:00", entry: deleted)
        #expect(validate([kept, orphan]) == [LineIssue(lineId: orphan.id, entryId: deleted, kind: .orphanLine)])
    }

    @Test func everyLineIsOrphanWhenTheDayHasNoEntries() {
        let l = line("09:00", "10:00")
        #expect(validate([l], entryIds: []) == [LineIssue(lineId: l.id, entryId: entry, kind: .orphanLine)])
    }

    @Test func emptyOrBlankDescriptionIsFlagged() {
        let empty = line("09:00", "10:00", description: "")
        let blank = line("10:00", "11:00", description: " \n\t ")
        #expect(validate([empty, blank]) == [
            LineIssue(lineId: empty.id, entryId: entry, kind: .emptyDescription),
            LineIssue(lineId: blank.id, entryId: entry, kind: .emptyDescription),
        ])
    }

    @Test func zeroLengthLine() {
        let l = line("10:00", "10:00")
        #expect(validate([l]) == [LineIssue(lineId: l.id, entryId: entry, kind: .endNotAfterStart)])
    }

    @Test func endBeforeStart() {
        let l = line("11:00", "10:00")
        #expect(validate([l]) == [LineIssue(lineId: l.id, entryId: entry, kind: .endNotAfterStart)])
    }

    @Test func afterWorkingHours() {
        let l = line("17:15", "17:45")
        #expect(validate([l]) == [LineIssue(lineId: l.id, entryId: entry, kind: .outsideWorkingHours)])
    }

    @Test func beforeWorkingHours() {
        let l = line("08:30", "09:30")
        #expect(validate([l]) == [LineIssue(lineId: l.id, entryId: entry, kind: .outsideWorkingHours)])
    }

    @Test func inLunch() {
        let l = line("12:15", "12:45")
        #expect(validate([l]) == [LineIssue(lineId: l.id, entryId: entry, kind: .inLunch)])
    }

    @Test func touchingLunchIsFine() {
        #expect(validate([line("11:00", "12:00"), line("13:00", "14:00")]).isEmpty)
    }

    @Test func noLunchWhenStartEqualsEnd() {
        var settings = AppSettings.default
        settings.workingHours.lunchStart = ClockTime(12, 0)
        settings.workingHours.lunchEnd = ClockTime(12, 0)
        #expect(validate([line("11:30", "12:30")], settings: settings).isEmpty)
    }

    @Test func overlapsFlaggedOnBoth() {
        let a = line("09:00", "10:00")
        let b = line("09:30", "10:30", entry: UUID())
        let issues = validate([a, b], entryIds: [a.entryId, b.entryId])
        #expect(issues == [
            LineIssue(lineId: a.id, entryId: a.entryId, kind: .overlaps(b.id)),
            LineIssue(lineId: b.id, entryId: b.entryId, kind: .overlaps(a.id)),
        ])
    }

    @Test func adjacentLinesDoNotOverlap() {
        #expect(validate([line("09:00", "10:00"), line("10:00", "11:00")]).isEmpty)
    }

    @Test func splitEntryAcrossLunchIsNotAnIssue() {
        #expect(validate([line("11:00", "12:00"), line("13:00", "14:00")]).isEmpty)
    }

    @Test func unknownActivityType() {
        let l = line("09:00", "10:00", activity: "Coding")
        #expect(validate([l]) == [LineIssue(lineId: l.id, entryId: entry, kind: .unknownActivityType)])
    }

    @Test func unknownClassification() {
        let l = line("09:00", "10:00", classification: "Free")
        #expect(validate([l]) == [LineIssue(lineId: l.id, entryId: entry, kind: .unknownClassification)])
    }

    @Test func invalidTicket() {
        let l = line("09:00", "10:00", ticket: "rsf1234")
        #expect(validate([l]) == [LineIssue(lineId: l.id, entryId: entry, kind: .invalidTicket)])
    }

    @Test func ticketMustMatchWholeString() {
        let l = line("09:00", "10:00", ticket: "see RSF-1234")
        #expect(validate([l]) == [LineIssue(lineId: l.id, entryId: entry, kind: .invalidTicket)])
    }

    @Test func nilOrEmptyTicketIsFine() {
        #expect(validate([line("09:00", "10:00", ticket: nil)]).isEmpty)
        #expect(validate([line("09:00", "10:00", ticket: "")]).isEmpty)
    }

    @Test func invalidPatternMeansNoConstraint() {
        var settings = AppSettings.default
        settings.template.ticketPattern = "[unclosed"
        #expect(validate([line("09:00", "10:00", ticket: "rsf1234")], settings: settings).isEmpty)
    }

    @Test func descriptionTooLong() {
        var settings = AppSettings.default
        settings.template.maxDescriptionLength = 10
        let l = line("09:00", "10:00", description: "12345678901")
        #expect(validate([l], settings: settings)
            == [LineIssue(lineId: l.id, entryId: entry, kind: .descriptionTooLong)])
        #expect(validate([line("09:00", "10:00", description: "1234567890")], settings: settings).isEmpty)
    }

    @Test func cleanFullDayHasNoIssues() {
        let other = UUID()
        let lines = [
            line("09:00", "12:00"),
            line("13:00", "15:00", entry: other, ticket: nil, activity: "Meeting", classification: "Internal"),
            line("15:00", "17:30"),
        ]
        #expect(validate(lines, entryIds: [entry, other]).isEmpty)
        #expect(LineValidator.totalMinutes(lines) == 450)
    }

    @Test func totalMinutesIgnoresInvertedLines() {
        #expect(LineValidator.totalMinutes([line("09:00", "10:00"), line("11:00", "10:00")]) == 60)
    }

    @Test func defaultWorkingMinutes() {
        #expect(LineValidator.workingMinutes(.default) == 450)
    }

    @Test func workingMinutesWithoutLunch() {
        var hours = WorkingHours.default
        hours.lunchEnd = hours.lunchStart
        #expect(LineValidator.workingMinutes(hours) == 510)
    }
}
