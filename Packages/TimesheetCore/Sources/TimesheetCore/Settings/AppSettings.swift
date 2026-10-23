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
    public var integrations: IntegrationSettings

    public init(
        template: TemplateSettings, activityTypes: [String], classifications: [String],
        workingHours: WorkingHours, model: ModelSelection, integrations: IntegrationSettings = .default
    ) {
        self.template = template
        self.activityTypes = activityTypes
        self.classifications = classifications
        self.workingHours = workingHours
        self.model = model
        self.integrations = integrations
    }

    public static let `default` = AppSettings(
        template: .default,
        activityTypes: ["Development", "Code Review", "Meeting", "Testing", "Documentation", "Support"],
        classifications: ["Billable", "Non-billable", "Internal"],
        workingHours: .default,
        model: .none)
}

// MARK: Decoding
// Every field falls back to its default when absent, so a settings file written by an older or
// newer version still loads instead of being reset.

extension TemplateSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TemplateSettings.default
        self.init(
            fields: try c.decodeIfPresent([TemplateField].self, forKey: .fields) ?? d.fields,
            separator: try c.decodeIfPresent(String.self, forKey: .separator) ?? d.separator,
            dateFormat: try c.decodeIfPresent(String.self, forKey: .dateFormat) ?? d.dateFormat,
            timeFormat: try c.decodeIfPresent(String.self, forKey: .timeFormat) ?? d.timeFormat,
            emptyTicketPlaceholder: try c.decodeIfPresent(String.self, forKey: .emptyTicketPlaceholder)
                ?? d.emptyTicketPlaceholder,
            separatorSubstitute: try c.decodeIfPresent(String.self, forKey: .separatorSubstitute)
                ?? d.separatorSubstitute,
            maxDescriptionLength: try c.decodeIfPresent(Int.self, forKey: .maxDescriptionLength)
                ?? d.maxDescriptionLength,
            ticketPattern: try c.decodeIfPresent(String.self, forKey: .ticketPattern) ?? d.ticketPattern)
    }
}

extension WorkingHours {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WorkingHours.default
        self.init(
            start: try c.decodeIfPresent(ClockTime.self, forKey: .start) ?? d.start,
            end: try c.decodeIfPresent(ClockTime.self, forKey: .end) ?? d.end,
            lunchStart: try c.decodeIfPresent(ClockTime.self, forKey: .lunchStart) ?? d.lunchStart,
            lunchEnd: try c.decodeIfPresent(ClockTime.self, forKey: .lunchEnd) ?? d.lunchEnd,
            roundingMinutes: try c.decodeIfPresent(Int.self, forKey: .roundingMinutes) ?? d.roundingMinutes)
    }
}

extension EndpointConfig {
    /// `baseURL` and `model` have no default; without them the selection is unreadable and becomes `.none`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            baseURL: try c.decode(URL.self, forKey: .baseURL),
            model: try c.decode(String.self, forKey: .model),
            remoteConfirmed: try c.decodeIfPresent(Bool.self, forKey: .remoteConfirmed) ?? false)
    }
}

extension AppSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        self.init(
            template: try c.decodeIfPresent(TemplateSettings.self, forKey: .template) ?? d.template,
            activityTypes: try c.decodeIfPresent([String].self, forKey: .activityTypes) ?? d.activityTypes,
            classifications: try c.decodeIfPresent([String].self, forKey: .classifications) ?? d.classifications,
            workingHours: try c.decodeIfPresent(WorkingHours.self, forKey: .workingHours) ?? d.workingHours,
            // An unknown or malformed selection (e.g. a source added later) means no model is chosen.
            model: (try? c.decodeIfPresent(ModelSelection.self, forKey: .model)) ?? ModelSelection.none,
            integrations: try c.decodeIfPresent(IntegrationSettings.self, forKey: .integrations) ?? d.integrations)
    }
}
