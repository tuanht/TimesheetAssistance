import Foundation

public enum TemplateField: String, Codable, CaseIterable, Sendable {
    case date, start, end, description, ticket, activityType, classification
}

public struct TemplateSettings: Codable, Equatable, Sendable {
    public var fields: [TemplateField]
    public var separator: String
    public var dateFormat: String
    public var timeFormat: String
    public var emptyTicketPlaceholder: String
    public var separatorSubstitute: String
    public var maxDescriptionLength: Int?
    public var ticketPattern: String

    public init(
        fields: [TemplateField], separator: String, dateFormat: String, timeFormat: String,
        emptyTicketPlaceholder: String, separatorSubstitute: String,
        maxDescriptionLength: Int?, ticketPattern: String
    ) {
        self.fields = fields
        self.separator = separator
        self.dateFormat = dateFormat
        self.timeFormat = timeFormat
        self.emptyTicketPlaceholder = emptyTicketPlaceholder
        self.separatorSubstitute = separatorSubstitute
        self.maxDescriptionLength = maxDescriptionLength
        self.ticketPattern = ticketPattern
    }

    public static let `default` = TemplateSettings(
        fields: [.date, .start, .end, .description, .ticket, .activityType, .classification],
        separator: " | ",
        dateFormat: "yyyy-MM-dd",
        timeFormat: "HH:mm",
        emptyTicketPlaceholder: "—",
        separatorSubstitute: "/",
        maxDescriptionLength: nil,
        ticketPattern: #"[A-Z][A-Z0-9]+-\d+"#
    )
}

public struct WorkingHours: Codable, Equatable, Sendable {
    public var start: ClockTime
    public var end: ClockTime
    public var lunchStart: ClockTime
    public var lunchEnd: ClockTime
    public var roundingMinutes: Int

    public init(start: ClockTime, end: ClockTime, lunchStart: ClockTime, lunchEnd: ClockTime, roundingMinutes: Int) {
        self.start = start
        self.end = end
        self.lunchStart = lunchStart
        self.lunchEnd = lunchEnd
        self.roundingMinutes = roundingMinutes
    }

    public static let `default` = WorkingHours(
        start: ClockTime(9, 0), end: ClockTime(17, 30),
        lunchStart: ClockTime(12, 0), lunchEnd: ClockTime(13, 0),
        roundingMinutes: 15)
}

public struct EndpointConfig: Codable, Equatable, Sendable {
    public var baseURL: URL
    public var model: String
    public var remoteConfirmed: Bool

    public init(baseURL: URL, model: String, remoteConfirmed: Bool) {
        self.baseURL = baseURL
        self.model = model
        self.remoteConfirmed = remoteConfirmed
    }
}

public enum ModelSelection: Codable, Equatable, Sendable {
    case none
    case local(repoId: String)
    case endpoint(EndpointConfig)
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var template: TemplateSettings
    public var activityTypes: [String]
    public var classifications: [String]
    public var workingHours: WorkingHours
    public var model: ModelSelection

    public init(
        template: TemplateSettings, activityTypes: [String], classifications: [String],
        workingHours: WorkingHours, model: ModelSelection
    ) {
        self.template = template
        self.activityTypes = activityTypes
        self.classifications = classifications
        self.workingHours = workingHours
        self.model = model
    }

    public static let `default` = AppSettings(
        template: .default,
        activityTypes: ["Development", "Code Review", "Meeting", "Testing", "Documentation", "Support"],
        classifications: ["Billable", "Non-billable", "Internal"],
        workingHours: .default,
        model: .none)
}
