import Foundation

public enum EntryType: String, Codable, CaseIterable, Sendable {
    case ticket, note, pullRequest, meeting

    public var displayName: String {
        switch self {
        case .ticket: "Ticket"
        case .note: "Note"
        case .pullRequest: "Pull request"
        case .meeting: "Meeting notes"
        }
    }
}

/// Immutable copy of one work entry, taken when compiling the day.
public struct EntrySnapshot: Equatable, Sendable {
    public var id: UUID
    public var type: EntryType
    public var ticketRef: String?
    public var durationHint: String?
    public var text: String

    public init(id: UUID, type: EntryType, ticketRef: String?, durationHint: String?, text: String) {
        self.id = id
        self.type = type
        self.ticketRef = ticketRef
        self.durationHint = durationHint
        self.text = text
    }
}
