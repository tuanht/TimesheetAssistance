import Foundation
import MLXGuidedGeneration
import Testing
import TimesheetCore
@testable import LocalModels

struct GuidedJSONTests {
    /// Printable ASCII, one character per token, so a reply is fed to the grammar exactly as written.
    private static let firstChar: UInt8 = 0x20
    private static let vocab = (firstChar ... 0x7E).map { String(UnicodeScalar($0)) } + ["</s>"]
    private static let eos = Int32(vocab.count - 1)

    private let schema = ResponseSchema.json(
        keys: ["e1", "e2"], activityTypes: ["Development", "Meeting"], classifications: ["Billable"])

    private func tokenizer() throws -> GrammarTokenizer {
        try GrammarTokenizer(vocab: Self.vocab, vocabType: .raw, eosTokenId: Self.eos)
    }

    private func allows(_ mask: MaskResult, _ token: Int32) -> Bool {
        let word = UInt32(bitPattern: mask.mask[Int(token) / 32])
        return (word >> (UInt32(token) % 32)) & 1 == 1
    }

    private func accepts(_ json: String, schema: String) throws -> Bool {
        let constraint = try GrammarConstraint(tokenizer: tokenizer(), jsonSchema: schema, fastForward: false)
        for byte in json.utf8 {
            let token = Int32(byte - Self.firstChar)
            guard allows(try constraint.computeMask(), token) else { return false }
            do { _ = try constraint.commitToken(token) } catch { return false }
        }
        let mask = try constraint.computeMask()
        return mask.isTerminated || allows(mask, Self.eos)
    }

    // Properties appear in the schema's prompt order, which the grammar enforces.
    private func item(_ key: String, activityType: String = "Development", ticket: String = "null") -> String {
        #"{"key":"\#(key)","minutes":30,"fixedStart":null,"fixedEnd":null,"description":"Work","#
            + #""ticket":\#(ticket),"activityType":"\#(activityType)","classification":"Billable"}"#
    }

    private func reply(_ items: [String]) -> String {
        #"{"items":[\#(items.joined(separator: ","))]}"#
    }

    @Test func compileSchemaIsAcceptedByXGrammar() throws {
        _ = try GrammarConstraint(tokenizer: tokenizer(), jsonSchema: schema)
    }

    @Test func validReplyIsAccepted() throws {
        #expect(try accepts(reply([item("e1", ticket: #""ABC-123""#), item("e2")]), schema: schema))
    }

    @Test func unknownActivityTypeIsRejected() throws {
        #expect(try !accepts(reply([item("e1", activityType: "Coding"), item("e2")]), schema: schema))
    }

    @Test func wrongKeyOrderIsRejected() throws {
        #expect(try !accepts(reply([item("e2"), item("e1")]), schema: schema))
    }

    @Test func missingItemIsRejected() throws {
        #expect(try !accepts(reply([item("e1")]), schema: schema))
    }

    @Test func guidedFailuresFallBack() {
        #expect(GuidedJSON.fallbackReason(for: GuidedGenerationError.incompleteOutput) == "incompleteOutput")
        #expect(GuidedJSON.fallbackReason(for: GuidedGenerationError.prematureEOS) == "prematureEOS")
        #expect(GuidedJSON.fallbackReason(for: GrammarError.maskComputationFailed("x")) == "maskComputationFailed")
    }

    @Test func fallbackReasonNamesOnlyTheCase() {
        #expect(GuidedJSON.fallbackReason(for: GrammarError.commitFailed("token=7")) == "commitFailed")
    }

    @Test func otherErrorsAreRethrown() {
        #expect(GuidedJSON.fallbackReason(for: CancellationError()) == nil)
        #expect(GuidedJSON.fallbackReason(for: LLMError.timeout) == nil)
    }

    @Test func setupFailureFallsBack() throws {
        #expect(throws: GrammarError.self) {
            try GrammarConstraint(tokenizer: tokenizer(), jsonSchema: "not json")
        }
    }
}
