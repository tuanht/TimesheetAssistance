import AppKit
import Foundation
import LocalModels
import SwiftData
import TimesheetCore

/// Compiles a range of days, one model call per day, keeps each day saved as its own `CompiledDay`,
/// and re-validates after every edit.
@MainActor
final class CompileViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case running(done: Int, total: Int)
        case failed(String)
    }

    /// Only the days in range that have entries or a saved result, oldest first.
    @Published private(set) var days: [DayResult] = []
    @Published var state = State.idle
    @Published private(set) var storeError: String?

    let range: DayRange
    private let context: ModelContext
    private let settings: SettingsStore
    private let models: MLXModelManager
    private var task: Task<Void, Never>?

    init(range: DayRange, context: ModelContext, settings: SettingsStore, models: MLXModelManager) {
        self.range = range
        self.context = context
        self.settings = settings
        self.models = models
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var isSingleDay: Bool { range.keys().count == 1 }

    /// Every line, in day order then by start.
    var lines: [DatedLine] {
        days.flatMap { result in
            Self.sorted(result.lines).map { DatedLine(day: result.day, line: $0) }
        }
    }

    var issues: [LineIssue] { days.flatMap(\.issues) }

    var entryCount: Int { days.reduce(0) { $0 + $1.entryIds.count } }

    var daysWithEntries: Int { days.filter { !$0.entryIds.isEmpty }.count }

    /// Days a compile would overwrite.
    var savedDaysToReplace: Int { days.filter { !$0.entryIds.isEmpty && $0.hasSaved }.count }

    var preview: String {
        LineRenderer.render(days: days.map { (day: $0.day, lines: $0.lines) }, template: settings.settings.template)
    }

    var totalMinutes: Int { LineValidator.totalMinutes(days.flatMap(\.lines)) }

    /// The working day times the days that have entries.
    var expectedMinutes: Int {
        LineValidator.workingMinutes(settings.settings.workingHours) * daysWithEntries
    }

    var clientPlan: ClientPlan {
        ClientPlan.resolve(settings.settings.model, isDownloaded: models.isDownloaded)
    }

    /// Gates both Compile and Retry.
    var canCompile: Bool { clientPlan.isUsable && entryCount > 0 }

    /// The day that owns a line, for its row's warnings.
    func dayResult(containing lineId: TimesheetLine.ID) -> DayResult? {
        days.first { $0.lines.contains { $0.id == lineId } }
    }

    /// Reads the range's entries and saved results.
    func load() {
        do {
            _ = try read()
            storeError = nil
        } catch {
            storeError = "Couldn’t read these days: \(error.localizedDescription)"
        }
        revalidate()
    }

    /// Starts a compile in the background, replacing any compile still running.
    func start() {
        task?.cancel()
        task = Task { await compile() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    func compile() async {
        let plan = clientPlan
        guard let client = LLMClientFactory.make(plan, models: models) else {
            // The model can change after the button was enabled; say why instead of doing nothing.
            if case .unavailable(let reason) = plan { state = .failed(reason.message) }
            return
        }
        let entries: [LogEntry]
        do {
            entries = try read()
        } catch {
            state = .failed("Couldn’t read the entries: \(error.localizedDescription)")
            return
        }
        revalidate()
        let byKey = Dictionary(grouping: entries.map { ($0.dayKey, $0.snapshot) }, by: \.0)
        let work = zip(range.keys(), range.days()).compactMap { key, day -> (key: String, day: Date, snapshots: [EntrySnapshot])? in
            guard let group = byKey[key] else { return nil }
            return (key, day, group.map(\.1))
        }
        let current = settings.settings
        // One call per day, oldest first; each day is saved as soon as it finishes.
        for (index, item) in work.enumerated() {
            if Task.isCancelled { return }
            state = .running(done: index, total: work.count)
            do {
                // Waits its turn behind any context summary using the same model.
                let result = try await ModelGate.shared.run {
                    try await Compiler(client: client).compile(entries: item.snapshots, day: item.day, settings: current)
                }
                try Task.checkCancellation()
                guard let at = days.firstIndex(where: { DayKey.string(for: $0.day) == item.key }) else { continue }
                days[at].lines = result.lines
                days[at].issues = result.issues
                do {
                    try persist(at, compiledAt: Date())
                    storeError = nil
                } catch {
                    // Stop here: a later day's save must not hide this one's failure.
                    let date = Period.label(.day, anchor: item.day)
                    state = .failed("\(date): Couldn’t save the compiled lines: \(error.localizedDescription)")
                    return
                }
            } catch {
                // A cancelled compile leaves state to `cancel()` or the compile that replaced it.
                if Task.isCancelled { return }
                let date = Period.label(.day, anchor: item.day)
                state = CompileFailure.message(for: error).map { .failed("\(date): \($0)") } ?? .idle
                return
            }
        }
        state = .idle
    }

    func revalidate() {
        days.indices.forEach(revalidate)
    }

    /// Applies an edit to one row in place, re-validates and saves its day. Reads the row fresh,
    /// so a cell's stale copy can't undo another cell's edit.
    func edit(_ id: TimesheetLine.ID, _ change: (inout TimesheetLine) -> Void) {
        guard let at = days.firstIndex(where: { $0.lines.contains { $0.id == id } }),
              let current = days[at].lines.first(where: { $0.id == id }) else { return }
        var line = current
        change(&line)
        guard line != current else { return }
        days[at].lines = LineEditing.replacing(line, in: days[at].lines)
        revalidate(at)
        save(at, compiledAt: nil)
    }

    /// Removes lines, re-validates and saves each day they came from. Compiling again brings them back.
    func delete(_ ids: Set<TimesheetLine.ID>) {
        for at in days.indices where days[at].lines.contains(where: { ids.contains($0.id) }) {
            days[at].lines.removeAll { ids.contains($0.id) }
            revalidate(at)
            save(at, compiledAt: nil)
        }
    }

    func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(preview, forType: .string)
    }

    /// Rebuilds `days` from the store and returns the range's entries. Days are matched by key, never by instant.
    private func read() throws -> [LogEntry] {
        let entries = try Store.entries(in: range, in: context)
        let saved = try Store.compiled(in: range, in: context)
        let idsByKey = Dictionary(grouping: entries, by: \.dayKey).mapValues { $0.map(\.id) }
        let linesByKey = Dictionary(saved.map { ($0.dayKey, $0.lines) }, uniquingKeysWith: { first, _ in first })
        days = zip(range.keys(), range.days()).compactMap { key, day in
            let ids = idsByKey[key] ?? []
            let lines = linesByKey[key]
            guard !ids.isEmpty || lines != nil else { return nil }
            return DayResult(day: day, entryIds: ids, lines: lines ?? [], issues: [], hasSaved: lines != nil)
        }
        return entries
    }

    private func revalidate(_ at: Int) {
        days[at].issues = LineValidator.validate(days[at].lines, entryIds: days[at].entryIds, settings: settings.settings)
    }

    /// Stable sort by start, matching the order `LineRenderer` prints.
    private static func sorted(_ lines: [TimesheetLine]) -> [TimesheetLine] {
        lines.enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
    }

    /// Saves an edit or delete; a failure is shown as `storeError`.
    private func save(_ at: Int, compiledAt: Date?) {
        do {
            try persist(at, compiledAt: compiledAt)
            storeError = nil
        } catch {
            storeError = "Couldn’t save the compiled lines: \(error.localizedDescription)"
        }
    }

    /// Upserts one day's `CompiledDay`; `compiledAt` is kept for edits and set for a fresh compile.
    /// Rolls back and rethrows on failure.
    private func persist(_ at: Int, compiledAt: Date?) throws {
        let result = days[at]
        do {
            if let saved = try Store.compiled(on: result.day, in: context) {
                saved.lines = result.lines
                if let compiledAt { saved.compiledAt = compiledAt }
            } else {
                context.insert(CompiledDay(day: result.day, lines: result.lines, compiledAt: compiledAt ?? Date()))
            }
            try context.save()
            days[at].hasSaved = true
        } catch {
            context.rollback()
            throw error
        }
    }
}
