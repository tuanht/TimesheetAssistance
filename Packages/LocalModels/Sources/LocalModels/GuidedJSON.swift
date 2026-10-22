import Foundation
import MLX
import MLXGuidedGeneration
import MLXLMCommon

/// XGrammar's copy of one model's vocabulary, plus the whitespace penalty that keeps a greedy run from padding
/// the JSON with blank tokens. Read-only once built, like the library's own `TokenizerBias`.
final class GrammarVocabulary: @unchecked Sendable {
    let tokenizer: GrammarTokenizer
    let whitespaceBias: MLXArray
    let whitespaceTokenIDs: Set<Int>

    init(tokenizer: GrammarTokenizer, whitespaceBias: MLXArray, whitespaceTokenIDs: Set<Int>) {
        self.tokenizer = tokenizer
        self.whitespaceBias = whitespaceBias
        self.whitespaceTokenIDs = whitespaceTokenIDs
    }
}

/// Glue between the model's tokenizer and XGrammar, used to force the local model's reply to match a JSON Schema.
enum GuidedJSON {
    /// Builds XGrammar's view of the vocabulary and the whitespace bias. Walks the whole vocab, so callers cache it.
    static func vocabulary(for tokenizer: any MLXLMCommon.Tokenizer) throws -> GrammarVocabulary {
        let vocab = TokenizerVocabExtractor.extractForGrammar(from: tokenizer)
        let grammarTokenizer = try GrammarTokenizer(
            vocab: vocab.vocab, vocabType: vocab.vocabType, eosTokenId: Int32(tokenizer.eosTokenId ?? 0))
        let whitespace = WhitespaceTokenBias.compute(tokenizer: tokenizer)
        return GrammarVocabulary(
            tokenizer: grammarTokenizer, whitespaceBias: whitespace.bias, whitespaceTokenIDs: whitespace.tokenIDs)
    }

    /// The guided loop decodes greedily, so a cut-off or grammar failure would repeat on every retry; for those
    /// the caller falls back to sampled, unconstrained decoding. Returns the error's case name (never its
    /// payload, which can quote output) for logging, or nil when the error should be rethrown.
    static func fallbackReason(for error: Error) -> String? {
        switch error {
        case let error as GuidedGenerationError:
            return "\(error)"
        case let error as GrammarError:
            return Mirror(reflecting: error).children.first?.label ?? "grammarError"
        default:
            return nil
        }
    }
}
