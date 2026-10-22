import Foundation
import SwiftData
import Testing
@testable import TimesheetCore

@MainActor
struct PersistenceTests {
    private let calendar = Calendar.current

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func line(_ description: String) -> TimesheetLine {
        TimesheetLine(
            entryId: UUID(), start: ClockTime(9, 0), end: ClockTime(10, 0),
            description: description, ticket: "ABC-1", activityType: "Dev", classification: "Billable")
    }

    @Test func entriesFilteredByDay() throws {
        let context = ModelContext(try Store.inMemory())
        let first = LogEntry(day: date(2026, 10, 22, 15), type: .ticket, ticketRef: "ABC-1", durationHint: nil, text: "first")
        first.createdAt = date(2026, 10, 22, 9)
        let second = LogEntry(day: date(2026, 10, 22, 8), type: .note, ticketRef: nil, durationHint: "1h", text: "second")
        second.createdAt = date(2026, 10, 22, 10)
        let other = LogEntry(day: date(2026, 10, 23, 9), type: .meeting, ticketRef: nil, durationHint: nil, text: "other")
        context.insert(second)
        context.insert(other)
        context.insert(first)
        try context.save()

        let result = try Store.entries(on: date(2026, 10, 22, 12), in: context)
        #expect(result.map(\.text) == ["first", "second"])
    }

    @Test func dayNormalisedToStartOfDay() {
        let entry = LogEntry(day: date(2026, 10, 22, 17, 45), type: .pullRequest, ticketRef: nil, durationHint: nil, text: "pr")
        #expect(entry.day == calendar.startOfDay(for: date(2026, 10, 22)))
        #expect(entry.type == .pullRequest)
        #expect(entry.snapshot == EntrySnapshot(id: entry.id, type: .pullRequest, ticketRef: nil, durationHint: nil, text: "pr"))

        let compiled = CompiledDay(day: date(2026, 10, 22, 17, 45), lines: [], compiledAt: date(2026, 10, 22, 18))
        #expect(compiled.day == calendar.startOfDay(for: date(2026, 10, 22)))
    }

    @Test func compiledDayLinesRoundTrip() throws {
        let context = ModelContext(try Store.inMemory())
        let lines = [line("one"), line("two")]
        context.insert(CompiledDay(day: date(2026, 10, 22, 11), lines: lines, compiledAt: date(2026, 10, 22, 18)))
        try context.save()

        let fetched = try #require(try Store.compiled(on: date(2026, 10, 22, 20), in: context))
        #expect(fetched.lines == lines)
        #expect(fetched.compiledAt == date(2026, 10, 22, 18))
        #expect(try Store.compiled(on: date(2026, 10, 23), in: context) == nil)
    }

    @Test func corruptLinesDataGivesEmpty() {
        let compiled = CompiledDay(day: date(2026, 10, 22), lines: [line("x")], compiledAt: date(2026, 10, 22))
        compiled.linesData = Data("not json".utf8)
        #expect(compiled.lines == [])
    }

    @Test func compiledDayUniquePerDay() throws {
        let context = ModelContext(try Store.inMemory())
        context.insert(CompiledDay(day: date(2026, 10, 22, 9), lines: [line("old")], compiledAt: date(2026, 10, 22, 17)))
        try context.save()
        context.insert(CompiledDay(day: date(2026, 10, 22, 14), lines: [line("new")], compiledAt: date(2026, 10, 22, 18)))
        try context.save()

        let all = try context.fetch(FetchDescriptor<CompiledDay>())
        #expect(all.count == 1)
        #expect(all.first?.lines.map(\.description) == ["new"])
    }

    @Test func fileContainerPersistsAcrossContainers() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("store.sqlite")
        do {
            let context = ModelContext(try Store.container(url: url))
            context.insert(LogEntry(day: date(2026, 10, 22), type: .note, ticketRef: nil, durationHint: nil, text: "kept"))
            try context.save()
        }
        let reopened = ModelContext(try Store.container(url: url))
        #expect(try Store.entries(on: date(2026, 10, 22), in: reopened).map(\.text) == ["kept"])
    }
}
