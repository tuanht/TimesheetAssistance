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

    @Test func entriesInRangeSortedByDayThenCreation() throws {
        let context = ModelContext(try Store.inMemory())
        let late = LogEntry(day: date(2026, 10, 22), type: .note, ticketRef: nil, durationHint: nil, text: "22 late")
        late.createdAt = date(2026, 10, 22, 15)
        let early = LogEntry(day: date(2026, 10, 22), type: .note, ticketRef: nil, durationHint: nil, text: "22 early")
        early.createdAt = date(2026, 10, 22, 9)
        let first = LogEntry(day: date(2026, 10, 21), type: .note, ticketRef: nil, durationHint: nil, text: "21")
        first.createdAt = date(2026, 10, 23, 9)
        let outside = LogEntry(day: date(2026, 10, 26), type: .note, ticketRef: nil, durationHint: nil, text: "26")
        for entry in [late, outside, early, first] { context.insert(entry) }
        try context.save()

        let range = DayRange(from: date(2026, 10, 20), to: date(2026, 10, 25), calendar: calendar)
        let result = try Store.entries(in: range, in: context, calendar: calendar)
        #expect(result.map(\.text) == ["21", "22 early", "22 late"])
    }

    @Test func compiledInRangeSortedByDay() throws {
        let context = ModelContext(try Store.inMemory())
        for day in [23, 21, 30] {
            context.insert(CompiledDay(day: date(2026, 10, day), lines: [line("x")], compiledAt: date(2026, 10, day, 18)))
        }
        try context.save()

        let range = DayRange(from: date(2026, 10, 20), to: date(2026, 10, 25), calendar: calendar)
        let result = try Store.compiled(in: range, in: context, calendar: calendar)
        #expect(result.map(\.dayKey) == ["2026-10-21", "2026-10-23"])
    }

    @Test func moveChangesDayKey() throws {
        let context = ModelContext(try Store.inMemory())
        let entry = LogEntry(day: date(2026, 10, 22, 10), type: .note, ticketRef: nil, durationHint: nil, text: "moved")
        context.insert(entry)
        try context.save()

        entry.move(to: date(2026, 10, 24, 23, 30))
        try context.save()

        #expect(entry.dayKey == "2026-10-24")
        #expect(try Store.entries(on: date(2026, 10, 22), in: context).isEmpty)
        #expect(try Store.entries(on: date(2026, 10, 24), in: context).map(\.text) == ["moved"])
    }

    @Test func dayStoredAsCalendarDateKey() {
        let entry = LogEntry(day: date(2026, 10, 22, 17, 45), type: .pullRequest, ticketRef: nil, durationHint: nil, text: "pr")
        #expect(entry.dayKey == "2026-10-22")
        #expect(entry.type == .pullRequest)
        #expect(entry.snapshot == EntrySnapshot(id: entry.id, type: .pullRequest, ticketRef: nil, durationHint: nil, text: "pr"))

        let compiled = CompiledDay(day: date(2026, 10, 22, 17, 45), lines: [], compiledAt: date(2026, 10, 22, 18))
        #expect(compiled.dayKey == "2026-10-22")
    }

    @Test func dayKeyUsesTheGivenTimeZone() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-22T23:30:00Z"))
        #expect(DayKey.string(for: instant, timeZone: try #require(TimeZone(identifier: "UTC"))) == "2026-10-22")
        #expect(DayKey.string(for: instant, timeZone: try #require(TimeZone(identifier: "Asia/Tokyo"))) == "2026-10-23")
        #expect(DayKey.string(for: instant, timeZone: try #require(TimeZone(identifier: "America/Los_Angeles"))) == "2026-10-22")
    }

    @Test func dataWrittenInOneTimeZoneIsFoundInAnother() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        func instant(_ hour: Int, in zone: TimeZone) throws -> Date {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            return try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: hour)))
        }
        let context = ModelContext(try Store.inMemory())
        context.insert(LogEntry(day: try instant(10, in: berlin), type: .note, ticketRef: nil, durationHint: nil,
                                text: "berlin", timeZone: berlin))
        context.insert(CompiledDay(day: try instant(10, in: berlin), lines: [line("berlin")],
                                   compiledAt: try instant(18, in: berlin), timeZone: berlin))
        try context.save()

        // 23:00 in New York on the 22nd is already the 23rd in Berlin; the calendar date still matches.
        let query = try instant(23, in: newYork)
        #expect(try Store.entries(on: query, in: context, timeZone: newYork).map(\.text) == ["berlin"])
        #expect(try Store.compiled(on: query, in: context, timeZone: newYork)?.lines.map(\.description) == ["berlin"])
        #expect(try Store.entries(on: query, in: context, timeZone: berlin).isEmpty)
        #expect(try Store.compiled(on: query, in: context, timeZone: berlin) == nil)
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

    @Test func overbookedDaySurvivesSaveAndReload() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("store.sqlite")
        var late = line("late")
        late.start = ClockTime(23, 30)
        late.end = ClockTime(24, 30)
        var later = line("later")
        later.start = ClockTime(24, 30)
        later.end = ClockTime(26, 0)
        let lines = [line("early"), late, later]
        do {
            let context = ModelContext(try Store.container(url: url))
            context.insert(CompiledDay(day: date(2026, 10, 22), lines: lines, compiledAt: date(2026, 10, 22, 18)))
            try context.save()
        }
        let reopened = ModelContext(try Store.container(url: url))
        let fetched = try #require(try Store.compiled(on: date(2026, 10, 22), in: reopened))
        #expect(fetched.lines == lines)
    }

    @Test func corruptLineDropsOnlyThatLine() throws {
        let good = line("good")
        let compiled = CompiledDay(day: date(2026, 10, 22), lines: [good], compiledAt: date(2026, 10, 22))
        var array = try #require(try JSONSerialization.jsonObject(with: compiled.linesData) as? [[String: Any]])
        var bad = array[0]
        bad["start"] = "99:99"
        array.insert(bad, at: 0)
        array.append(["description": "missing fields"])
        compiled.linesData = try JSONSerialization.data(withJSONObject: array)
        #expect(compiled.lines == [good])
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

    @Test func cloudKitDisabledInEveryConfiguration() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // CloudKitDatabase is not Equatable; its reflection exposes the _none flag.
        let none = String(reflecting: ModelConfiguration.CloudKitDatabase.none)
        for container in [try Store.inMemory(), try Store.container(url: dir.appendingPathComponent("store.sqlite"))] {
            #expect(!container.configurations.isEmpty)
            for configuration in container.configurations {
                #expect(String(reflecting: configuration.cloudKitDatabase) == none)
            }
        }
    }

    @Test func fileContainerCompiledDayUniquePerDay() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("store.sqlite")
        do {
            let context = ModelContext(try Store.container(url: url))
            context.insert(CompiledDay(day: date(2026, 10, 22, 9), lines: [line("old")], compiledAt: date(2026, 10, 22, 17)))
            try context.save()
            context.insert(CompiledDay(day: date(2026, 10, 22, 14), lines: [line("new")], compiledAt: date(2026, 10, 22, 18)))
            try context.save()
            let all = try context.fetch(FetchDescriptor<CompiledDay>())
            #expect(all.count == 1)
            #expect(all.first?.lines.map(\.description) == ["new"])
        }
        do {
            let context = ModelContext(try Store.container(url: url))
            context.insert(CompiledDay(day: date(2026, 10, 22, 16), lines: [line("newest")], compiledAt: date(2026, 10, 22, 19)))
            try context.save()
        }
        let reopened = ModelContext(try Store.container(url: url))
        let all = try reopened.fetch(FetchDescriptor<CompiledDay>())
        #expect(all.count == 1)
        #expect(all.first?.lines.map(\.description) == ["newest"])
        #expect(all.first?.compiledAt == date(2026, 10, 22, 19))
    }

    private func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
