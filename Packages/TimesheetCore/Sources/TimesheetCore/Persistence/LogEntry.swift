import Foundation
import SwiftData

/// One work entry the user logged for a day.
@Model
public final class LogEntry {
    @Attribute(.unique) public var id: UUID
    /// Always `Calendar.current.startOfDay`, so day queries can match on equality.
    public var day: Date
    public var typeRaw: String
    public var ticketRef: String?
    public var durationHint: String?
    public var text: String
    public var createdAt: Date

    public init(day: Date, type: EntryType, ticketRef: String?, durationHint: String?, text: String) {
        self.id = UUID()
        self.day = Calendar.current.startOfDay(for: day)
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

    public var snapshot: EntrySnapshot {
        EntrySnapshot(id: id, type: type, ticketRef: ticketRef, durationHint: durationHint, text: text)
    }
}
