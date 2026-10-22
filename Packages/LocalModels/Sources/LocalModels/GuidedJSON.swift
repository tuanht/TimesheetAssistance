import Foundation
import MLXGuidedGeneration
import MLXLMCommon
import TimesheetCore

/// Glue between the model's tokenizer and XGrammar, used to force the local model's reply to match a JSON Schema.
enum GuidedJSON {
    /// Builds XGrammar's view of the vocabulary. Walks the whole vocab, so callers cache the result.
    static func grammarTokenizer(for tokenizer: any MLXLMCommon.Tokenizer) throws -> GrammarTokenizer {
        let vocab = TokenizerVocabExtractor.extractForGrammar(from: tokenizer)
        return try GrammarTokenizer(
            vocab: vocab.vocab, vocabType: vocab.vocabType, eosTokenId: Int32(tokenizer.eosTokenId ?? 0))
    }

    /// A reply the grammar never finished, or one it stopped mid-way, is cut off; the user gets
    /// `LLMError.incompleteResponse` instead of XGrammar's technical text.
    static func mapError(_ error: Error) -> Error {
        error is GuidedGenerationError || error is GrammarError ? LLMError.incompleteResponse : error
    }
}
