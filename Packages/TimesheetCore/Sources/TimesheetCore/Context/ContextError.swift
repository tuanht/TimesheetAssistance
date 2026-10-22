import Foundation

/// Why fetching an entry's context failed. Messages never include tokens, arguments or fetched text.
public enum ContextError: Error, Equatable, Sendable {
    case notConnected(IntegrationService)
    case notFound(String)                 // canonical ref
    case unreachable(IntegrationService)
    case signInAgain(IntegrationService)
    case notApproved(IntegrationService)
    case unexpectedReply(IntegrationService)
    /// A programming error: only allow-listed read tools may be called.
    case toolNotAllowed(String)

    public var userMessage: String {
        switch self {
        case .notConnected(let service):
            "\(service.displayName) not connected"
        case .notFound(let ref):
            // Canonical PR refs are "owner/repo#45"; Jira keys never contain "#".
            ref.contains("#") ? "Couldn't find \(ref) on GitHub." : "Couldn't find \(ref) in Jira."
        case .unreachable(let service):
            "Couldn't reach \(service.displayName). Check your connection and try again."
        case .signInAgain(let service):
            "Sign in to \(service.displayName) again in Settings › Integrations."
        case .notApproved(.github):
            "Your organization hasn't approved this app for GitHub. Ask an admin, or use a personal token instead."
        case .notApproved(.jira):
            "Your organization hasn't enabled this for Jira. Ask an admin, or switch sign-in method in Settings › Integrations."
        case .unexpectedReply(let service):
            "\(service.displayName) sent a reply the app couldn't read. Try again later."
        case .toolNotAllowed:
            "The app tried an action it isn't allowed to use."
        }
    }
}
