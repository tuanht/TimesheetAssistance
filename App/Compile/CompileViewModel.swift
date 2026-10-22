import AppKit
import Foundation
import LocalModels
import SwiftData
import TimesheetCore

/// Compiles one day's entries into timesheet lines, keeps them saved as the day's `CompiledDay`,
/// and re-validates after every edit.
@MainActor
final class CompileViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case failed(String)
    }

    @Published var lines: [TimesheetLine] = []
    @Published var issues: [LineIssue] = []
    @Published var state = State.idle
    @Published private(set) var entryCount = 0
    /// True once the day has a saved result, so compiling again asks before replacing it.
    @Published private(set) var hasSavedResult = false
    @Published private(set) var storeError: String?

    let day: Date
    private let context: ModelContext
    private let settings: SettingsStore
    private let models: MLXModelManager
    private var entryIds: [UUID] = []
    private var task: Task<Void, Never>?

    init(day: Date, context: ModelContext, settings: SettingsStore, models: MLXModelManager) {
        self.day = Calendar.current.startOfDay(for: day)
        self.context = context
        self.settings = settings
        self.models = models
    }

    var preview: String {
        LineRenderer.render(lines, day: day, template: settings.settings.template)
    }

    var totalMinutes: Int { LineValidator.totalMinutes(lines) }

    var workingMinutes: Int { LineValidator.workingMinutes(settings.settings.workingHours) }

    var clientPlan: ClientPlan {
        ClientPlan.resolve(settings.settings.model, isDownloaded: models.isDownloaded)
    }

    /// Gates both Compile and Retry.
    var canCompile: Bool { clientPlan.isUsable && entryCount > 0 }

    /// Reads the day's entries and its saved result, if any.
    func load() {
        do {
            entryIds = try Store.entries(on: day, in: context).map(\.id)
            entryCount = entryIds.count
            if let saved = try Store.compiled(on: day, in: context) {
                lines = saved.lines
                hasSavedResult = true
            }
            storeError = nil
        } catch {
            storeError = "Couldn’t read this day: \(error.localizedDescription)"
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
        guard let client = makeClient(plan) else {
            // The model can change after the button was enabled; say why instead of doing nothing.
            if case .unavailable(let reason) = plan { state = .failed(reason.message) }
            return
        }
        let snapshots: [EntrySnapshot]
        do {
            let entries = try Store.entries(on: day, in: context)
            snapshots = entries.map(\.snapshot)
            entryIds = entries.map(\.id)
            entryCount = entries.count
        } catch {
            state = .failed("Couldn’t read this day’s entries: \(error.localizedDescription)")
            return
        }
        state = .running
        let current = settings.settings
        do {
            let result = try await Compiler(client: client).compile(entries: snapshots, day: day, settings: current)
            try Task.checkCancellation()
            lines = result.lines
            issues = result.issues
            save(compiledAt: Date())
            state = .idle
        } catch {
            // A cancelled compile leaves state to `cancel()` or the compile that replaced it.
            if Task.isCancelled { return }
            state = CompileFailure.message(for: error).map(State.failed) ?? .idle
        }
    }

    func revalidate() {
        issues = LineValidator.validate(lines, entryIds: entryIds, settings: settings.settings)
    }

    /// Applies an edit to one row in place, re-validates and saves. Reads the row fresh, so a
    /// cell's stale copy can't undo another cell's edit.
    func edit(_ id: TimesheetLine.ID, _ change: (inout TimesheetLine) -> Void) {
        guard let current = lines.first(where: { $0.id == id }) else { return }
        var line = current
        change(&line)
        guard line != current else { return }
        lines = LineEditing.replacing(line, in: lines)
        revalidate()
        save(compiledAt: nil)
    }

    func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(preview, forType: .string)
    }

    private func makeClient(_ plan: ClientPlan) -> LLMClient? {
        switch plan {
        case .local(let repoId):
            return models.client(for: repoId)
        case .endpoint(let config):
            return OpenAICompatibleClient(
                config: config, apiKey: KeychainStore.get(account: KeychainStore.apiKeyAccount))
        case .unavailable:
            return nil
        }
    }

    /// Upserts the day's `CompiledDay`; `compiledAt` is kept for edits and set for a fresh compile.
    private func save(compiledAt: Date?) {
        do {
            if let saved = try Store.compiled(on: day, in: context) {
                saved.lines = lines
                if let compiledAt { saved.compiledAt = compiledAt }
            } else {
                context.insert(CompiledDay(day: day, lines: lines, compiledAt: compiledAt ?? Date()))
            }
            try context.save()
            hasSavedResult = true
            storeError = nil
        } catch {
            context.rollback()
            storeError = "Couldn’t save the compiled lines: \(error.localizedDescription)"
        }
    }
}
