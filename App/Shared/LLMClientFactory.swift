import Foundation
import LocalModels
import TimesheetCore

/// Builds the client for a resolved `ClientPlan`, shared by compile and context summaries.
@MainActor
enum LLMClientFactory {
    static func make(_ plan: ClientPlan, models: MLXModelManager) -> LLMClient? {
        switch plan {
        case .local(let repoId):
            return models.client(for: repoId)
        case .endpoint(let config):
            return OpenAICompatibleClient(
                config: config, apiKey: KeychainStore.get(account: KeychainStore.apiKeyAccount))
        case .unavailable:
            return nil
        }
    }
}
