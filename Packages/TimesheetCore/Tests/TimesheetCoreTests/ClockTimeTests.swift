import Foundation
import Testing
@testable import TimesheetCore

struct ClockTimeTests {
    @Test func roundsDownToStep() {
        #expect(ClockTime("09:07")?.rounded(to: 15) == ClockTime(9, 0))
    }

    @Test func roundsTiesUp() {
        #expect(ClockTime(9, 8).rounded(to: 15) == ClockTime(9, 15))
    }

    @Test func rejectsOutOfRange() {
        #expect(ClockTime("25:00") == nil)
        #expect(ClockTime("12:60") == nil)
        #expect(ClockTime("garbage") == nil)
    }

    @Test func formatsHHmm() {
        #expect(ClockTime(17, 30).hhmm == "17:30")
        #expect(ClockTime(9, 5).hhmm == "09:05")
    }

    @Test func codableAsString() throws {
        let data = try JSONEncoder().encode([ClockTime(9, 5)])
        #expect(String(data: data, encoding: .utf8) == "[\"09:05\"]")
        #expect(try JSONDecoder().decode([ClockTime].self, from: data) == [ClockTime(9, 5)])
    }

    @Test func decodesTimesPastMidnightUpTo4759() throws {
        let data = Data(#"["24:30","47:59"]"#.utf8)
        #expect(try JSONDecoder().decode([ClockTime].self, from: data) == [ClockTime(24, 30), ClockTime(47, 59)])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([ClockTime].self, from: Data(#"["48:00"]"#.utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([ClockTime].self, from: Data(#"["24:60"]"#.utf8)) }
    }

    @Test func encodesTimesPastMidnightLiterally() throws {
        let data = try JSONEncoder().encode([ClockTime(24, 30)])
        #expect(String(data: data, encoding: .utf8) == "[\"24:30\"]")
    }

    @Test func comparable() {
        #expect(ClockTime(9, 0) < ClockTime(9, 1))
    }
}
