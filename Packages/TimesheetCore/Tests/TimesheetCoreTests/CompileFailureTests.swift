import Foundation
import Testing
@testable import TimesheetCore

struct CompileFailureTests {
    @Test func cancellationShowsNothing() {
        #expect(CompileFailure.message(for: CancellationError()) == nil)
    }

    @Test func llmErrorUsesItsUserMessage() {
        #expect(CompileFailure.message(for: LLMError.timeout) == LLMError.timeout.userMessage)
    }

    @Test func modelLoadFailureIsReadable() {
        #expect(CompileFailure.message(for: LLMError.modelLoadFailed)
            == "Couldn't load the model. Delete it in Settings › Models and download it again.")
    }

    @Test(arguments: [ParseError.noJSON, .invalidJSON("raw model output {\"items\":")])
    func parseErrorIsReadableAndHidesModelOutput(error: ParseError) {
        let message = CompileFailure.message(for: error)
        #expect(message == "The model's reply couldn't be read. Try again, or try another model.")
    }

    @Test func noEntries() {
        #expect(CompileFailure.message(for: CompileError.noEntries) == "No entries for this day.")
    }

    @Test func otherErrorsStillGetAMessage() {
        struct Odd: Error {}
        #expect(CompileFailure.message(for: Odd())?.hasPrefix("Compiling failed") == true)
    }
}
