import Foundation

/// Turns a model's summary reply into plain text.
public enum SummaryParser {
    /// Strips <think> blocks and a wrapping code fence, trims; throws LLMError.emptyResponse when nothing is left.
    public static func clean(_ reply: String) throws -> String {
        var text = ResponseParser.strippingThinkBlocks(reply).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = ResponseParser.fencedBlocks(in: text).first ?? ""
        }
        guard !text.isEmpty else { throw LLMError.emptyResponse }
        return text
    }
}
