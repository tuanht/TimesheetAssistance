import Testing
@testable import TimesheetCore

struct TicketDetectorTests {
    @Test func findsFirstMatch() {
        #expect(TicketDetector.firstTicket(in: "Fixed login for ABC-123, then XY-9", pattern: #"[A-Z][A-Z0-9]+-\d+"#) == "ABC-123")
    }

    @Test func noMatchIsNil() {
        #expect(TicketDetector.firstTicket(in: "refactored the scheduler", pattern: #"[A-Z][A-Z0-9]+-\d+"#) == nil)
    }

    @Test func invalidPatternIsNil() {
        #expect(TicketDetector.firstTicket(in: "ABC-123", pattern: "[") == nil)
    }

    @Test func emptyPatternIsNil() {
        #expect(TicketDetector.firstTicket(in: "ABC-123", pattern: "") == nil)
    }
}
