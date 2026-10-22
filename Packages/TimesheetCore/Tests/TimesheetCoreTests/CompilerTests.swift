import Foundation
import Testing
@testable import TimesheetCore

/// Returns canned text (or throws) and records the prompt it received.
final class FakeLLMClient: LLMClient, @unchecked Sendable {
    private let result: Result<String, Error>
    private let lock = NSLock()
    private var _received: [(system: String, user: String)] = []

    init(_ text: String) { result = .success(text) }
    init(error: Error) { result = .failure(error) }

    var received: [(system: String, user: String)] {
        lock.withLock { _received }
    }

    func complete(system: String, user: String) async throws -> String {
        lock.withLock { _received.append((system, user)) }
        return try result.get()
    }
}

struct CompilerTests {
    let settings = AppSettings.default
    let day = Date(timeIntervalSince1970: 1_792_627_200)

    func entry(_ text: String, type: EntryType = .ticket, ticketRef: String? = nil, hint: String? = nil) -> EntrySnapshot {
        EntrySnapshot(id: UUID(), type: type, ticketRef: ticketRef, durationHint: hint, text: text)
    }

    func item(_ key: String, minutes: Int = 60, fixedStart: String? = nil, fixedEnd: String? = nil,
              description: String = "Did work", ticket: String? = nil,
              activity: String = "Development", classification: String = "Billable") -> String {
        func json(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "null" }
        return """
        {"key":"\(key)","minutes":\(minutes),"fixedStart":\(json(fixedStart)),"fixedEnd":\(json(fixedEnd)),\
        "description":\(json(description)),"ticket":\(json(ticket)),\
        "activityType":"\(activity)","classification":"\(classification)"}
        """
    }

    func response(_ items: String...) -> String {
        #"{"items":["# + items.joined(separator: ",") + "]}"
    }

    func compile(_ entries: [EntrySnapshot], _ text: String) async throws -> (CompileResult, FakeLLMClient) {
        let client = FakeLLMClient(text)
        let result = try await Compiler(client: client).compile(entries: entries, day: day, settings: settings)
        return (result, client)
    }

    @Test func happyPath() async throws {
        let entries = [entry("Fixed login bug", ticketRef: "ABC-1"), entry("Reviewed PR 42", type: .pullRequest)]
        let (result, client) = try await compile(entries, response(
            item("e1", minutes: 120, description: "Fixed login bug"),
            item("e2", minutes: 60, description: "  Reviewed PR  ", activity: "Code Review")))

        #expect(result.issues.isEmpty)
        #expect(result.lines.count >= 2)
        #expect(Set(result.lines.map(\.entryId)) == Set(entries.map(\.id)))
        #expect(LineValidator.totalMinutes(result.lines) == LineValidator.workingMinutes(settings.workingHours))
        #expect(result.lines.first?.start == ClockTime(9, 0))
        #expect(result.lines.last?.end == ClockTime(17, 30))
        #expect(Set(result.lines.map(\.id)).count == result.lines.count)

        let review = try #require(result.lines.first { $0.entryId == entries[1].id })
        #expect(review.description == "Reviewed PR")
        #expect(review.activityType == "Code Review")
        #expect(review.classification == "Billable")

        let expected = PromptBuilder.build(entries: entries, day: day, settings: settings)
        #expect(client.received.count == 1)
        #expect(client.received.first?.system == expected.system)
        #expect(client.received.first?.user == expected.user)
    }

    @Test func entryTicketOverridesModelTicket() async throws {
        let entries = [entry("Work", ticketRef: "ABC-1"), entry("Other work")]
        let (result, _) = try await compile(entries, response(
            item("e1", ticket: "XYZ-9"), item("e2", ticket: "DEF-2")))

        #expect(result.lines.filter { $0.entryId == entries[0].id }.allSatisfy { $0.ticket == "ABC-1" })
        #expect(result.lines.filter { $0.entryId == entries[1].id }.allSatisfy { $0.ticket == "DEF-2" })
    }

    @Test func ticketDetectedFromTextWhenModelOmitsIt() async throws {
        let entries = [entry("Reviewed PROJ-42 rollout")]
        let (result, _) = try await compile(entries, response(item("e1", ticket: nil)))
        #expect(!result.lines.isEmpty)
        #expect(result.lines.allSatisfy { $0.ticket == "PROJ-42" })
    }

    @Test func entryTicketBeatsDetectedAndModel() async throws {
        let entries = [entry("Follow-up on BB-2", ticketRef: "AA-1")]
        let (result, _) = try await compile(entries, response(item("e1", ticket: "CC-3")))
        #expect(!result.lines.isEmpty)
        #expect(result.lines.allSatisfy { $0.ticket == "AA-1" })
    }

    @Test func detectedBeatsModel() async throws {
        let entries = [entry("Follow-up on BB-2")]
        let (result, _) = try await compile(entries, response(item("e1", ticket: "CC-3")))
        #expect(!result.lines.isEmpty)
        #expect(result.lines.allSatisfy { $0.ticket == "BB-2" })
    }

    @Test func skippedEntryStillGetsDetectedTicket() async throws {
        let entries = [entry("Work"), entry("Follow-up on BB-2")]
        let (result, _) = try await compile(entries, response(item("e1")))
        let skipped = result.lines.filter { $0.entryId == entries[1].id }
        #expect(!skipped.isEmpty)
        #expect(skipped.allSatisfy { $0.ticket == "BB-2" })
    }

    @Test func ticketTypeDisplayName() {
        #expect(EntryType.ticket.displayName == "Ticket")
    }

    @Test func blankModelTicketIsNil() async throws {
        let entries = [entry("Work")]
        let (result, _) = try await compile(entries, response(item("e1", ticket: "  ")))
        #expect(result.lines.allSatisfy { $0.ticket == nil })
    }

    @Test func skippedEntryStillGetsLine() async throws {
        let longText = String(repeating: "x", count: 100)
        let entries = [entry("Work"), entry(longText)]
        let (result, _) = try await compile(entries, response(item("e1")))

        let skipped = result.lines.filter { $0.entryId == entries[1].id }
        #expect(!skipped.isEmpty)
        #expect(skipped.allSatisfy { $0.description == String(repeating: "x", count: 80) })
        #expect(skipped.allSatisfy { $0.activityType.isEmpty && $0.classification.isEmpty })
        #expect(result.issues.contains { $0.entryId == entries[1].id && $0.kind == .unknownActivityType })
        #expect(result.issues.contains { $0.entryId == entries[1].id && $0.kind == .unknownClassification })
        #expect(!result.issues.contains { $0.kind == .missingLine })
    }

    @Test func unknownKeyIgnored() async throws {
        let entries = [entry("Work")]
        let (result, _) = try await compile(entries, response(item("e1"), item("e9")))

        #expect(Set(result.lines.map(\.entryId)) == [entries[0].id])
        #expect(result.issues.isEmpty)
    }

    @Test func duplicateKeyUsesFirstItem() async throws {
        let entries = [entry("Work")]
        let (result, _) = try await compile(entries, response(
            item("e1", description: "First"), item("e1", description: "Second")))
        #expect(result.lines.allSatisfy { $0.description == "First" })
    }

    @Test func emptyDayThrowsNoEntries() async throws {
        let client = FakeLLMClient("unused")
        await #expect(throws: CompileError.noEntries) {
            try await Compiler(client: client).compile(entries: [], day: day, settings: settings)
        }
        #expect(client.received.isEmpty)
    }

    @Test func clientErrorPropagates() async throws {
        let client = FakeLLMClient(error: LLMError.timeout)
        await #expect(throws: LLMError.timeout) {
            try await Compiler(client: client).compile(entries: [entry("Work")], day: day, settings: settings)
        }
    }

    @Test func cancellationPropagatesUnchanged() async throws {
        let client = FakeLLMClient(error: CancellationError())
        await #expect(throws: CancellationError.self) {
            try await Compiler(client: client).compile(entries: [entry("Work")], day: day, settings: settings)
        }
    }

    @Test func parseErrorPropagates() async throws {
        await #expect(throws: ParseError.noJSON) {
            _ = try await compile([entry("Work")], "no json here")
        }
    }

    @Test func meetingFixedTimeKept() async throws {
        let entries = [entry("Work"), entry("Standup at 14:00", type: .meeting)]
        let (result, _) = try await compile(entries, response(
            item("e1"),
            item("e2", minutes: 30, fixedStart: "14:00", fixedEnd: "14:30", activity: "Meeting")))

        let meeting = result.lines.filter { $0.entryId == entries[1].id }
        #expect(meeting.count == 1)
        #expect(meeting.first?.start == ClockTime(14, 0))
        #expect(meeting.first?.end == ClockTime(14, 30))
        #expect(result.issues.isEmpty)
    }

    @Test func halfFixedTimeIsNotFixed() async throws {
        let entries = [entry("Work"), entry("Meeting", type: .meeting)]
        let (result, _) = try await compile(entries, response(
            item("e1"), item("e2", fixedStart: "14:00", fixedEnd: "25:99")))

        #expect(!result.lines.contains { $0.start == ClockTime(14, 0) })
        #expect(result.issues.isEmpty)
        #expect(LineValidator.totalMinutes(result.lines) == LineValidator.workingMinutes(settings.workingHours))
    }

    @Test func invertedFixedTimeIsNotFixed() async throws {
        let entries = [entry("Meeting", type: .meeting)]
        let (result, _) = try await compile(entries, response(
            item("e1", fixedStart: "15:00", fixedEnd: "14:00")))
        #expect(result.issues.isEmpty)
        #expect(result.lines.first?.start == ClockTime(9, 0))
    }

    @Test func durationHintUsed() async throws {
        let entries = [entry("Work", hint: "~2h"), entry("Other")]
        let (result, _) = try await compile(entries, response(item("e1", minutes: 10), item("e2", minutes: 10)))
        let minutes = result.lines.filter { $0.entryId == entries[0].id }
            .reduce(0) { $0 + $1.end.minutes - $1.start.minutes }
        #expect(minutes == 120)
    }
}
