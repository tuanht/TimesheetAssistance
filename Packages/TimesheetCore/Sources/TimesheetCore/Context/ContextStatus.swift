import Foundation

/// Progress or outcome of an entry's context job, as shown under the entry.
public enum ContextStatus: Equatable, Sendable {
    case fetching(String)                 // canonical ref
    case summarizing
    /// `failures` are problems to fix; `notes` are refs skipped because their optional service isn't
    /// connected, so they aren't shown as errors. Both are userMessages, in order.
    case finished(failures: [String], notes: [String])

    /// Progress text; nil once finished.
    public var text: String? {
        switch self {
        case .fetching(let ref): "Fetching \(ref)…"
        case .summarizing: "Summarizing…"
        case .finished: nil
        }
    }

    public var failureText: String? {
        guard case .finished(let failures, _) = self, !failures.isEmpty else { return nil }
        return failures.joined(separator: "\n")
    }

    public var noteText: String? {
        guard case .finished(_, let notes) = self, !notes.isEmpty else { return nil }
        return notes.joined(separator: "\n")
    }
}
