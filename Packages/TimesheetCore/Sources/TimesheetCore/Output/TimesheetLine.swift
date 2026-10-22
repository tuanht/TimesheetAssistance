import Foundation

public struct TimesheetLine: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var entryId: UUID
    public var start: ClockTime
    public var end: ClockTime
    public var description: String
    public var ticket: String?
    public var activityType: String
    public var classification: String

    public init(
        id: UUID = UUID(), entryId: UUID, start: ClockTime, end: ClockTime, description: String,
        ticket: String?, activityType: String, classification: String
    ) {
        self.id = id
        self.entryId = entryId
        self.start = start
        self.end = end
        self.description = description
        self.ticket = ticket
        self.activityType = activityType
        self.classification = classification
    }
}
