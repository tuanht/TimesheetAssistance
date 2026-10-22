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

    @Test func validDraftInsideThinkBlockIgnored() throws {
        let draft = #"{"items":[{"key":"e9","minutes":5,"description":"Draft","activityType":"Support","classification":"Internal"}]}"#
        let text = "<think>First draft: \(draft) wait, fix it</think>\n\(json)"
        #expect(try ResponseParser.parse(text) == expected)
    }

    func item(_ body: String) throws -> [ModelItem] {
        try ResponseParser.parse(#"{"items":["# + body + "]}")
    }

    @Test func nullActivityTypeBecomesEmpty() throws {
        let items = try item(#"{"key":"e1","minutes":60,"description":"D","activityType":null,"classification":"Billable"}"#)
        #expect(items.count == 1)
        #expect(items.first?.activityType == "")
    }

    @Test func missingDescriptionBecomesEmpty() throws {
        let items = try item(#"{"key":"e1","minutes":60,"activityType":"Meeting","classification":"Billable"}"#)
        #expect(items.first?.description == "")
    }

    @Test func missingOrBadMinutesBecomes30() throws {
        let items = try item(#"{"key":"e1","description":"D","activityType":"A","classification":"C"},{"key":"e2","minutes":"lots","description":"D","activityType":"A","classification":"C"},{"key":"e3","minutes":null,"description":"D","activityType":"A","classification":"C"}"#)
        #expect(items.map(\.minutes) == [30, 30, 30])
    }

    @Test func itemWithoutKeyDroppedOthersSurvive() throws {
        let items = try item(#"{"minutes":10,"description":"No key"},{"key":"","minutes":10},{"key":"e2","minutes":45,"description":"Kept","activityType":"A","classification":"C"},"junk""#)
        #expect(items.map(\.key) == ["e2"])
        #expect(items.first?.minutes == 45)
    }

    @Test func objectWithoutItemsThrowsInvalidJSON() {
        do {
            _ = try ResponseParser.parse(#"{"entries":[]}"#)
            Issue.record("expected throw")
        } catch let error as ParseError {
            guard case .invalidJSON = error else { Issue.record("got \(error)"); return }
        } catch { Issue.record("unexpected \(error)") }
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
