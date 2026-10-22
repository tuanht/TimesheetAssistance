import Foundation
import SwiftData

/// One work entry the user logged for a day.
@Model
public final class LogEntry {
    @Attribute(.unique) public var id: UUID
    /// The calendar date it was logged for, from `DayKey`.
    public var dayKey: String
    public var typeRaw: String
    public var ticketRef: String?
    public var durationHint: String?
    public var text: String
    public var createdAt: Date
    /// LLM summary of the referenced tickets and PRs; raw ticket text is never stored.
    public var contextSummary: String? = nil
    public var contextRefs: [String]? = nil
    /// Set when the user edited the summary, so a refresh must ask before overwriting it.
    public var contextEdited: Bool = false
    public var contextUpdatedAt: Date? = nil

    /// `day` is read as a calendar date in `timeZone`.
    public init(
        day: Date, type: EntryType, ticketRef: String?, durationHint: String?, text: String,
        timeZone: TimeZone = .current
    ) {
        self.id = UUID()
        self.dayKey = DayKey.string(for: day, timeZone: timeZone)
        self.typeRaw = type.rawValue
        self.ticketRef = ticketRef
        self.durationHint = durationHint
        self.text = text
        self.createdAt = Date()
    }

    /// Unknown raw values fall back to `.note` rather than crashing on old data.
    public var type: EntryType {
        get { EntryType(rawValue: typeRaw) ?? .note }
        set { typeRaw = newValue.rawValue }
    }

    /// Moves the entry to the calendar date of `day` in `timeZone`.
    public func move(to day: Date, timeZone: TimeZone = .current) {
        dayKey = DayKey.string(for: day, timeZone: timeZone)
    }

    public var snapshot: EntrySnapshot {
        let summary = contextSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? contextSummary : nil
        return EntrySnapshot(
            id: id, type: type, ticketRef: ticketRef, durationHint: durationHint, text: text, contextSummary: summary)
    }
}
