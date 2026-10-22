import Foundation
import MLXGuidedGeneration
import MLXLLM
import MLXLMCommon
import TimesheetCore

/// Runs one downloaded model on this Mac. The model loads on the first `complete` and stays loaded.
public actor MLXClient: LLMClient {
    static let temperature: Float = 0.2
    static let maxTokens = 2048

    private let directory: URL
    private var loading: Task<ModelContainer, Error>? {
        didSet { grammarTokenizer = nil }
    }
    /// XGrammar's copy of the loaded model's vocabulary; slow to build, so it lives as long as the model.
    private var grammarTokenizer: GrammarTokenizer?

    init(directory: URL) {
        self.directory = directory
    }

    /// Throws `LLMError.modelNotReady` when the weights aren't on disk, `LLMError.modelLoadFailed` when they
    /// can't be loaded, and `CancellationError` when cancelled.
    public func complete(system: String, user: String) async throws -> String {
        try await complete(system: system, user: user, jsonSchema: nil)
    }

    /// With a `jsonSchema`, decoding is constrained to it and a reply cut off mid-JSON throws
    /// `LLMError.incompleteResponse`. A schema XGrammar can't compile falls back to unconstrained decoding.
    public func complete(system: String, user: String, jsonSchema: String?) async throws -> String {
        let container = try await container()
        try Task.checkCancellation()

        var text: String?
        if let jsonSchema, !jsonSchema.isEmpty {
            text = try await guided(container, system: system, user: user, jsonSchema: jsonSchema)
        }
        if text == nil {
            text = try await unconstrained(container, system: system, user: user)
        }
        try Task.checkCancellation()

        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMError.emptyResponse }
        return trimmed
    }

    private func unconstrained(_ container: ModelContainer, system: String, user: String) async throws -> String {
        let prepared = try await container.prepare(input: Self.chat(system: system, user: user))
        let parameters = GenerateParameters(maxTokens: Self.maxTokens, temperature: Self.temperature)

        var text = ""
        // Generation runs on the library's own worker; a cancelled caller ends the stream and stops it.
        for await generation in try await container.generate(input: prepared, parameters: parameters) {
            if let chunk = generation.chunk { text += chunk }
        }
        return text
    }

    /// Returns nil when the grammar can't be set up, so the caller falls back to unconstrained decoding.
    private func guided(
        _ container: ModelContainer, system: String, user: String, jsonSchema: String
    ) async throws -> String? {
        let cached = grammarTokenizer
        let generation = loading
        let (tokenizer, text): (GrammarTokenizer?, String?) = try await container.perform { context in
            let input = try await context.processor.prepare(input: Self.chat(system: system, user: user))
            let tokenizer: GrammarTokenizer
            let constraint: GrammarConstraint
            do {
                tokenizer = try cached ?? GuidedJSON.grammarTokenizer(for: context.tokenizer)
                constraint = try GrammarConstraint(
                    tokenizer: tokenizer, jsonSchema: jsonSchema, fastForward: true,
                    hostTokenizer: context.tokenizer)
            } catch is GrammarError {
                return (nil, nil)
            }

            var output = ""
            do {
                // The guided loop samples greedily, so `temperature` doesn't apply here.
                try GuidedGenerationLoop.run(
                    input: input, context: context, constraint: constraint,
                    maxTokens: Self.maxTokens, vocabSize: tokenizer.vocabSize
                ) { delta in
                    output += delta
                    return !Task.isCancelled
                }
            } catch {
                // A cancel that lands at the token limit surfaces as `incompleteOutput`; it's still a cancel.
                if Task.isCancelled { throw CancellationError() }
                throw GuidedJSON.mapError(error)
            }
            return (tokenizer, output)
        }
        // A model reloaded meanwhile may have another vocabulary, so only cache against the same load.
        if let tokenizer, loading == generation { grammarTokenizer = tokenizer }
        return text
    }

    /// Templates without a thinking switch ignore `enable_thinking`; Qwen3 skips its <think> block.
    private static func chat(system: String, user: String) -> UserInput {
        UserInput(chat: [.system(system), .user(user)], additionalContext: ["enable_thinking": false])
    }

    private func container() async throws -> ModelContainer {
        guard ModelStorage.isComplete(directory) else {
            loading = nil
            throw LLMError.modelNotReady
        }
        if let loading { return try await Self.mapLoadError { try await loading.value } }
        let directory = directory
        let task = Task {
            try await LLMModelFactory.shared.loadContainer(
                from: directory, using: TransformersTokenizerLoader())
        }
        loading = task
        do {
            return try await Self.mapLoadError { try await task.value }
        } catch {
            // A failed load is retried on the next call.
            if loading == task { loading = nil }
            throw error
        }
    }

    /// The library's load errors are raw and technical; the user gets `LLMError.modelLoadFailed` instead.
    private static func mapLoadError<T>(_ load: () async throws -> T) async throws -> T {
        do {
            return try await load()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LLMError.modelLoadFailed
        }
    }
}
