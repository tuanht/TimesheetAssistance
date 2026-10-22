import Foundation

/// What to do with an entry's context after a save or a refresh request.
public enum ContextAction: Equatable, Sendable {
    case none, fetch, confirmReplace, clear
}

/// Decides when an entry's context is fetched, replaced, cleared or applied.
public enum ContextPolicy {
    /// On save. `current` = DetectedReferences.canonical; `stored` = LogEntry.contextRefs.
    public static func onSave(current: [String], stored: [String]?, hasSummary: Bool, edited: Bool) -> ContextAction {
        if current.isEmpty { return hasSummary && !edited ? .clear : .none }
        // Same refs without a summary means the previous job never finished.
        if current == stored { return hasSummary ? .none : .fetch }
        return edited ? .confirmReplace : .fetch
    }

    /// Refresh button.
    public static func onRefresh(current: [String], edited: Bool) -> ContextAction {
        if current.isEmpty { return .none }
        return edited ? .confirmReplace : .fetch
    }

    /// Whether a finished job may write its summary. `jobRefs` = refs the job started with.
    /// The coordinator stores `jobRefs` when a job starts, so a later save that changes refs rejects it.
    public static func shouldApply(jobRefs: [String], currentRefs: [String]?, editedSinceStart: Bool) -> Bool {
        jobRefs == currentRefs && !editedSinceStart
    }
}
