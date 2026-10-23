import Foundation

/// A fetched Jira issue or pull request, held in memory only until it is summarized.
public struct FetchedSource: Equatable, Sendable {
    public var reference: ContextReference
    public var title: String
    public var state: String          // Jira status / PR state
    public var detail: String?        // Jira issue type, or "head → base" for a PR
    public var body: String           // description / PR body, uncapped

    public init(reference: ContextReference, title: String, state: String, detail: String?, body: String) {
        self.reference = reference
        self.title = title
        self.state = state
        self.detail = detail
        self.body = body
    }
}
