import Foundation

/// Progress or failure of an entry's context job, as shown under the entry.
public enum ContextStatus: Equatable, Sendable {
    case fetching(String)                 // canonical ref
    case summarizing
    case failed([String])                 // userMessages, in order

    public var text: String {
        switch self {
        case .fetching(let ref): "Fetching \(ref)…"
        case .summarizing: "Summarizing…"
        case .failed(let messages): messages.joined(separator: "\n")
        }
    }
}
