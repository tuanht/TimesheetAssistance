import Testing
@testable import TimesheetCore

struct SummaryParserTests {
    @Test func cleanStripsThink() throws {
        #expect(try SummaryParser.clean("<think>plan {x}</think>Adds CSV export.") == "Adds CSV export.")
    }

    @Test func cleanUnwrapsFence() throws {
        #expect(try SummaryParser.clean("```\nAdds CSV export.\n```") == "Adds CSV export.")
        #expect(try SummaryParser.clean("```text\nAdds CSV export.\n```") == "Adds CSV export.")
    }

    @Test func cleanTrims() throws {
        #expect(try SummaryParser.clean("  \n Adds CSV export. \n") == "Adds CSV export.")
    }

    @Test func cleanEmptyThrows() {
        #expect(throws: LLMError.emptyResponse) { try SummaryParser.clean("<think>x</think>  ") }
        #expect(throws: LLMError.emptyResponse) { try SummaryParser.clean("```\n```") }
    }
}
