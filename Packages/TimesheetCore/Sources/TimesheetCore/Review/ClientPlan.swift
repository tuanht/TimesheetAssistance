import Foundation

/// Which model the Compile screen may use for the current settings, decided without building a client.
public enum ClientPlan: Equatable, Sendable {
    case local(repoId: String)
    case endpoint(EndpointConfig)
    case unavailable(Unavailable)

    public enum Unavailable: Equatable, Sendable {
        case noModel
        case notDownloaded
        /// Entries never go to a non-local endpoint the user hasn't confirmed.
        case remoteNotConfirmed

        public var note: String {
            switch self {
            case .noModel: "No model is selected."
            case .notDownloaded: "The selected on-device model isn’t downloaded."
            case .remoteNotConfirmed: "The endpoint is outside this Mac and network and hasn’t been confirmed."
            }
        }
    }

    public static func resolve(_ selection: ModelSelection, isDownloaded: (String) -> Bool) -> ClientPlan {
        switch selection {
        case .none:
            return .unavailable(.noModel)
        case .local(let repoId):
            return isDownloaded(repoId) ? .local(repoId: repoId) : .unavailable(.notDownloaded)
        case .endpoint(let config):
            guard EndpointPolicy.isLocal(config.baseURL) || config.remoteConfirmed else {
                return .unavailable(.remoteNotConfirmed)
            }
            return .endpoint(config)
        }
    }
}
