import Foundation
import MLXLLM
import MLXLMCommon
import TimesheetCore

/// Runs one downloaded model on this Mac. The model loads on the first `complete` and stays loaded.
public actor MLXClient: LLMClient {
    static let temperature: Float = 0.2
    static let maxTokens = 2048

    private let directory: URL
    private var loading: Task<ModelContainer, Error>?

    init(directory: URL) {
        self.directory = directory
    }

    /// Throws `LLMError.modelNotReady` when the weights aren't on disk, and `CancellationError` when cancelled.
    public func complete(system: String, user: String) async throws -> String {
        let container = try await container()
        try Task.checkCancellation()

        // Templates without a thinking switch ignore `enable_thinking`; Qwen3 skips its <think> block.
        let input = UserInput(
            chat: [.system(system), .user(user)],
            additionalContext: ["enable_thinking": false])
        let prepared = try await container.prepare(input: input)
        let parameters = GenerateParameters(maxTokens: Self.maxTokens, temperature: Self.temperature)

        var text = ""
        // Generation runs on the library's own worker; a cancelled caller ends the stream and stops it.
        for await generation in try await container.generate(input: prepared, parameters: parameters) {
            if let chunk = generation.chunk { text += chunk }
        }
        try Task.checkCancellation()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMError.emptyResponse }
        return trimmed
    }

    private func container() async throws -> ModelContainer {
        guard ModelStorage.isComplete(directory) else {
            loading = nil
            throw LLMError.modelNotReady
        }
        if let loading { return try await loading.value }
        let directory = directory
        let task = Task {
            try await LLMModelFactory.shared.loadContainer(
                from: directory, using: TransformersTokenizerLoader())
        }
        loading = task
        do {
            return try await task.value
        } catch {
            // A failed load is retried on the next call.
            if loading == task { loading = nil }
            throw error
        }
    }
}
