import Foundation
import Testing
@testable import TimesheetCore

struct LineEditingTests {
    @Test(arguments: [("09:00", 540), ("9:05", 545), (" 17:30 ", 1050), ("00:00", 0), ("23:59", 1439)])
    func parsesTimes(text: String, minutes: Int) {
        #expect(LineEditing.time(from: text)?.minutes == minutes)
    }

    @Test(arguments: ["", "9", "930", "24:00", "12:60", "+9:00", "9:5", "09:00:00", "ab:cd", "-1:00", "１２:００"])
    func rejectsInvalidTimes(text: String) {
        #expect(LineEditing.time(from: text) == nil)
    }

    @Test func listedCurrentValueAddsNoOption() {
        #expect(LineEditing.choices(list: ["A", "B"], current: "B")
            == [ChoiceOption(value: "A", isListed: true), ChoiceOption(value: "B", isListed: true)])
    }

    @Test func unlistedCurrentValueIsAppendedAsInvalid() {
        #expect(LineEditing.choices(list: ["A"], current: "Z")
            == [ChoiceOption(value: "A", isListed: true), ChoiceOption(value: "Z", isListed: false)])
    }

    @Test func emptyCurrentValueIsAnInvalidOption() {
        #expect(LineEditing.choices(list: ["A"], current: "").last == ChoiceOption(value: "", isListed: false))
    }

    @Test func replacingALineKeepsEveryRowInPlace() {
        let entry = UUID()
        let a = TimesheetLine(entryId: entry, start: ClockTime(9, 0), end: ClockTime(10, 0),
                              description: "a", ticket: nil, activityType: "", classification: "")
        var b = a; b.id = UUID(); b.start = ClockTime(10, 0); b.end = ClockTime(11, 0)
        var c = a; c.id = UUID(); c.start = ClockTime(11, 0); c.end = ClockTime(12, 0)
        var edited = b
        edited.start = ClockTime(8, 0)
        let result = LineEditing.replacing(edited, in: [a, b, c])
        #expect(result.map(\.id) == [a.id, b.id, c.id])
        #expect(result[1] == edited)
        #expect(result[0] == a && result[2] == c)
    }

    @Test func replacingAnUnknownLineChangesNothing() {
        let a = TimesheetLine(entryId: UUID(), start: ClockTime(9, 0), end: ClockTime(10, 0),
                              description: "a", ticket: nil, activityType: "", classification: "")
        var other = a; other.id = UUID()
        #expect(LineEditing.replacing(other, in: [a]) == [a])
    }

    @Test(arguments: [("", nil), ("  ", nil), (" ABC-1 ", "ABC-1")] as [(String, String?)])
    func ticketFromText(text: String, ticket: String?) {
        #expect(LineEditing.ticket(from: text) == ticket)
    }
}
