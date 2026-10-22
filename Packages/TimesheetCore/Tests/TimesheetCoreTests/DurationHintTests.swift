import Testing
@testable import TimesheetCore

struct DurationHintTests {
    @Test(arguments: [
        ("~2h", 120), ("2h", 120), ("1.5h", 90), ("1h30m", 90), ("1h 30", 90),
        ("45m", 45), ("45 min", 45), ("90", 90), ("2H", 120), ("45 MIN", 45),
    ])
    func parsesDurations(text: String, minutes: Int) {
        #expect(DurationHint.minutes(from: text) == minutes)
    }

    @Test(arguments: ["soon", "", "h", "1.5", "2h later", "-1h"])
    func rejectsNonDurations(text: String) {
        #expect(DurationHint.minutes(from: text) == nil)
    }
}
