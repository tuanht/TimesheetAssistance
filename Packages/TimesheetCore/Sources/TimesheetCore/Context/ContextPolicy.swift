import Foundation

/// What to do with an entry's context after a save or a refresh request.
public enum ContextAction: Equatable, Sendable {
    case none, fetch, confirmReplace, clear
}

/// Decides when an entry's context is fetched, replaced, cleared or applied.
public enum ContextPolicy {
    /// On save. `current` = DetectedReferences.canonical; `stored` = LogEntry.contextRefs,
    /// the refs the current summary was built from (written only when a summary is applied).
    /// `hasSummary` = the summary is not blank. Blank + edited means the user opted out.
    public static func onSave(current: [String], stored: [String]?, hasSummary: Bool, edited: Bool) -> ContextAction {
        if current.isEmpty { return hasSummary && !edited ? .clear : .none }
        // Same refs without a summary means the previous job never finished, unless the user cleared it.
        if current == stored { return hasSummary || edited ? .none : .fetch }
        // An edited blank summary has nothing to replace.
        return edited && hasSummary ? .confirmReplace : .fetch
    }

    /// Refresh button. Confirms only when it would replace a summary the user edited.
    public static func onRefresh(current: [String], hasSummary: Bool, edited: Bool) -> ContextAction {
        if current.isEmpty { return .none }
        return edited && hasSummary ? .confirmReplace : .fetch
    }

    /// Whether a finished job may write its summary. `jobRefs` = refs the job started with;
    /// `currentRefs` = refs re-detected from the entry's current ticket and text, so a later
    /// save that changes refs rejects it.
    public static func shouldApply(jobRefs: [String], currentRefs: [String]?, editedSinceStart: Bool) -> Bool {
        jobRefs == currentRefs && !editedSinceStart
    }
}
