import Foundation

public struct CompileResult: Equatable, Sendable {
    public var lines: [TimesheetLine]
    public var issues: [LineIssue]

    public init(lines: [TimesheetLine], issues: [LineIssue]) {
        self.lines = lines
        self.issues = issues
    }
}

public enum CompileError: Error, Equatable, Sendable {
    case noEntries
}

/// Runs one day through prompt, model, parse, schedule and validation.
/// The model only supplies text fields and relative effort; the scheduler owns the clock.
public struct Compiler: Sendable {
    private let client: LLMClient

    public init(client: LLMClient) {
        self.client = client
    }

    public func compile(entries: [EntrySnapshot], day: Date, settings: AppSettings) async throws -> CompileResult {
        guard !entries.isEmpty else { throw CompileError.noEntries }

        let prompt = PromptBuilder.build(entries: entries, day: day, settings: settings)
        let text = try await client.complete(system: prompt.system, user: prompt.user)
        let modelItems = try ResponseParser.parse(text)

        var itemsById: [UUID: ModelItem] = [:]
        for item in modelItems {
            guard let id = prompt.keyMap[item.key], itemsById[id] == nil else { continue }
            itemsById[id] = item
        }

        let fields = entries.map { entry in
            LineFields(entry: entry, item: itemsById[entry.id])
        }
        let scheduleItems = zip(entries, fields).map { entry, f in
            ScheduleItem(
                entryId: entry.id,
                hintMinutes: DurationHint.minutes(from: entry.durationHint ?? ""),
                estimatedMinutes: f.estimatedMinutes,
                fixed: f.fixed)
        }
        let fieldsById = Dictionary(uniqueKeysWithValues: zip(entries.map(\.id), fields))

        let lines = Scheduler.schedule(scheduleItems, hours: settings.workingHours).compactMap { slot in
            fieldsById[slot.entryId].map { f in
                TimesheetLine(
                    id: UUID(), entryId: slot.entryId, start: slot.start, end: slot.end,
                    description: f.description, ticket: f.ticket,
                    activityType: f.activityType, classification: f.classification)
            }
        }
        let issues = LineValidator.validate(lines, entryIds: entries.map(\.id), settings: settings)
        return CompileResult(lines: lines, issues: issues)
    }
}

/// One entry's text fields and scheduling inputs, merged from the entry and the model's item.
private struct LineFields {
    var estimatedMinutes: Int
    var fixed: (start: ClockTime, end: ClockTime)?
    var description: String
    var ticket: String?
    var activityType: String
    var classification: String

    static let skippedMinutes = 30
    static let skippedDescriptionLength = 80

    init(entry: EntrySnapshot, item: ModelItem?) {
        let entryTicket = LineFields.nonBlank(entry.ticketRef)
        guard let item else {
            // Model skipped the entry: keep it, with empty fields the validator will flag.
            estimatedMinutes = LineFields.skippedMinutes
            fixed = nil
            description = String(entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(LineFields.skippedDescriptionLength))
            ticket = entryTicket
            activityType = ""
            classification = ""
            return
        }
        estimatedMinutes = item.minutes
        if let start = item.fixedStart.flatMap(ClockTime.init),
           let end = item.fixedEnd.flatMap(ClockTime.init), end > start {
            fixed = (start, end)
        } else {
            fixed = nil
        }
        description = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket = entryTicket ?? LineFields.nonBlank(item.ticket)
        activityType = item.activityType
        classification = item.classification
    }

    private static func nonBlank(_ s: String?) -> String? {
        guard let trimmed = s?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
