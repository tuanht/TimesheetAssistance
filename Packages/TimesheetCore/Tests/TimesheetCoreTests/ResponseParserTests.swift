import Foundation
import Testing
@testable import TimesheetCore

struct ResponseParserTests {
    let json = #"{"items":[{"key":"e1","minutes":60,"fixedStart":null,"fixedEnd":null,"description":"Fixed login bug","ticket":"ABC-1","activityType":"Development","classification":"Billable"}]}"#

    let expected = [ModelItem(key: "e1", minutes: 60, fixedStart: nil, fixedEnd: nil,
                              description: "Fixed login bug", ticket: "ABC-1",
                              activityType: "Development", classification: "Billable")]

    @Test func plainJSON() throws {
        #expect(try ResponseParser.parse(json) == expected)
    }

    @Test func jsonInsideCodeFence() throws {
        #expect(try ResponseParser.parse("```json\n\(json)\n```") == expected)
    }

    @Test func thinkBlockStripped() throws {
        let text = "<think>{\"x\":1} reasoning</think>\n\(json)"
        #expect(try ResponseParser.parse(text) == expected)
    }

    @Test func proseAroundJSON() throws {
        #expect(try ResponseParser.parse("Here you go: \(json) Hope it helps") == expected)
    }

    @Test func missingOptionalKeysDecode() throws {
        let text = #"{"items":[{"key":"e2","minutes":30,"description":"Standup","activityType":"Meeting","classification":"Internal"}]}"#
        let items = try ResponseParser.parse(text)
        #expect(items.first?.fixedStart == nil)
        #expect(items.first?.ticket == nil)
    }

    @Test func noJSONThrows() {
        #expect(throws: ParseError.noJSON) { try ResponseParser.parse("Sorry, I can't") }
    }

    @Test func truncatedJSONThrows() {
        do {
            _ = try ResponseParser.parse(#"{"items":[{"key":"e1""#)
            Issue.record("expected throw")
        } catch let error as ParseError {
            guard case .invalidJSON = error else {
                Issue.record("expected invalidJSON, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected \(error)")
        }
    }
}
