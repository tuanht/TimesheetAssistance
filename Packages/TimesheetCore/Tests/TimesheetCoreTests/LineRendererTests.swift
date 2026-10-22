import Foundation
import Testing
@testable import TimesheetCore

struct LineRendererTests {
    private let day: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 22; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    private func line(
        _ start: ClockTime = ClockTime(9, 0), _ end: ClockTime = ClockTime(10, 30),
        desc: String = "Implement pagination", ticket: String? = "RSF-1234"
    ) -> TimesheetLine {
        TimesheetLine(id: UUID(), entryId: UUID(), start: start, end: end, description: desc,
                      ticket: ticket, activityType: "Development", classification: "Billable")
    }

    @Test func defaultTemplate() {
        let out = LineRenderer.render([line()], day: day, template: .default)
        #expect(out == "2026-10-22 | 09:00 | 10:30 | Implement pagination | RSF-1234 | Development | Billable")
    }

    @Test func emptyTicketUsesPlaceholder() {
        let out = LineRenderer.render([line(ticket: nil)], day: day, template: .default)
        #expect(out.components(separatedBy: " | ")[4] == "—")
    }

    @Test func separatorInDescriptionIsSubstituted() {
        let out = LineRenderer.render([line(desc: "API | DB")], day: day, template: .default)
        #expect(out.components(separatedBy: " | ")[3] == "API / DB")
        #expect(out.components(separatedBy: " | ").count == 7)
    }

    @Test func newlineInDescriptionCollapses() {
        let lines = [line(desc: "line one\nline two"), line(ClockTime(11, 0), ClockTime(12, 0))]
        let out = LineRenderer.render(lines, day: day, template: .default)
        #expect(out.contains("line one line two"))
        #expect(out.filter { $0 == "\n" }.count == 1)
        #expect(!out.hasSuffix("\n"))
    }

    @Test func fieldOrderAndSeparatorAreRespected() {
        var t = TemplateSettings.default
        t.fields = [.ticket, .start, .description]
        t.separator = ";"
        let out = LineRenderer.render([line(desc: "Fix", ticket: "RSF-1")], day: day, template: t)
        #expect(out == "RSF-1;09:00;Fix")
    }

    @Test func linesSortedByStart() {
        let late = line(ClockTime(14, 0), ClockTime(15, 0), desc: "late")
        let early = line(ClockTime(9, 0), ClockTime(10, 0), desc: "early")
        let out = LineRenderer.render([late, early], day: day, template: .default)
        let rows = out.components(separatedBy: "\n")
        #expect(rows[0].contains("early"))
        #expect(rows[1].contains("late"))
    }

    @Test func maxDescriptionLengthTruncates() {
        var t = TemplateSettings.default
        t.maxDescriptionLength = 5
        t.fields = [.description]
        #expect(LineRenderer.render([line(desc: "abcdefgh")], day: day, template: t) == "abcde")
    }
}
