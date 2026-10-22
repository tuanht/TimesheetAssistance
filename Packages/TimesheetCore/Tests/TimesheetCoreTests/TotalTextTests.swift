import Testing
@testable import TimesheetCore

struct TotalTextTests {
    @Test(arguments: [(0, "0m"), (45, "45m"), (60, "1h"), (450, "7h 30m"), (481, "8h 1m")])
    func duration(minutes: Int, text: String) {
        #expect(TotalText.duration(minutes) == text)
    }

    @Test func total() {
        #expect(TotalText.total(450, of: 450) == "Total 7h 30m of 7h 30m")
        #expect(TotalText.total(390, of: 450) == "Total 6h 30m of 7h 30m")
    }
}
