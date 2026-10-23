import Testing
@testable import TimesheetCore

struct ClockMentionTests {
    @Test(arguments: [
        ("Standup 9:30", [ClockTime(9, 30)]),
        ("Workshop 11:00-14:00", [ClockTime(11, 0), ClockTime(14, 0)]),
        ("call at 2pm", [ClockTime(14, 0)]),
        ("12am", [ClockTime(0, 0)]),
        ("12pm", [ClockTime(12, 0)]),
        ("9:15 AM", [ClockTime(9, 15)]),
        ("sync 4:45pm", [ClockTime(16, 45)]),
        ("demo at 10 PM", [ClockTime(22, 0)]),
        ("from 09:00 to 3pm", [ClockTime(9, 0), ClockTime(15, 0)]),
        ("13:00 pm", [ClockTime(13, 0)]),
        ("9:30 amazing", [ClockTime(9, 30)]),
        ("10:00-11:30 sprint planning", [ClockTime(10, 0), ClockTime(11, 30)]),
    ])
    func recognised(text: String, expected: [ClockTime]) {
        #expect(ClockMention.times(in: text) == Set(expected))
    }

    @Test(arguments: [
        "Worked 7h on ABC-1",
        "1h30 review",
        "v1.2.3",
        "9.30",
        "25:00",
        "9:60",
        "13pm",
        "112:30",
        "1:2:3",
        "0am",
        "14h30",
        "at 2 amazing demos",
        "",
    ])
    func ignored(text: String) {
        #expect(ClockMention.times(in: text).isEmpty)
    }
}
