import SwiftData
import SwiftUI
import TimesheetCore

/// A saved entry whose new references would replace an edited summary.
private struct PendingReplace {
    let entry: LogEntry
}

/// Sheet that creates a new entry on the picked day, or edits `entry` in place.
struct EntryEditor: View {
    let entry: LogEntry?
    /// The day the sheet opened on; the entry moves only when the user picks another.
    private let initialDay: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var coordinator: ContextCoordinator
    @State private var day: Date
    @State private var type: EntryType
    @State private var ticketRef: String
    @State private var durationHint: String
    @State private var text: String
    @State private var summary: String
    /// The stored summary as last loaded, so only a change the user typed marks it edited.
    @State private var loadedSummary: String
    @State private var saveError: String?
    /// The saved entry awaiting "Replace" or "Keep" after a save.
    @State private var pendingReplace: PendingReplace?
    @State private var confirmingReplace = false
    @State private var confirmingRefresh = false

    /// A new entry starts on `defaultDay`; an existing one on the day of its `dayKey`.
    init(defaultDay: Date, entry: LogEntry?) {
        self.entry = entry
        initialDay = entry.flatMap { Self.date(forKey: $0.dayKey) } ?? defaultDay
        _day = State(initialValue: initialDay)
        _type = State(initialValue: entry?.type ?? .ticket)
        _ticketRef = State(initialValue: entry?.ticketRef ?? "")
        _durationHint = State(initialValue: entry?.durationHint ?? "")
        _text = State(initialValue: entry?.text ?? "")
        _summary = State(initialValue: entry?.contextSummary ?? "")
        _loadedSummary = State(initialValue: entry?.contextSummary ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry == nil ? "New Entry" : "Edit Entry").font(.title2)
            Form {
                Picker("Type", selection: $type) {
                    ForEach(EntryType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                LabeledContent("Day") {
                    CalendarButton(title: day.formatted(date: .abbreviated, time: .omitted), date: $day,
                                   accessibilityLabel: "Day")
                }
                TextField("Ticket", text: $ticketRef, prompt: Text(ticketPrompt))
                linkedLine
                TextField("Duration hint", text: $durationHint, prompt: Text("e.g. ~2h"))
            }
            Text("Text").font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 100, idealHeight: 220)
                .border(.separator)
                .accessibilityLabel("Entry text")
            contextSection
            if let saveError {
                Text(saveError).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(isTextBlank)
            }
        }
        .padding(20)
        // The text boxes shrink first; the main window's minimum height keeps this sheet from being clipped.
        .frame(minWidth: 520, idealWidth: 600, minHeight: 520, idealHeight: 640)
        // A finished job updates the stored summary; show it unless the user has typed over it.
        .onChange(of: entry?.contextSummary) { _, stored in
            if summary == loadedSummary { summary = stored ?? "" }
            loadedSummary = stored ?? ""
        }
        .confirmationDialog("References changed. Replace your edited summary?", isPresented: $confirmingReplace,
                            titleVisibility: .visible, presenting: pendingReplace) { pending in
            Button("Replace", role: .destructive) { finishReplace(pending, replace: true) }
            Button("Keep", role: .cancel) { finishReplace(pending, replace: false) }
        }
        .confirmationDialog("Replace your edited summary?", isPresented: $confirmingRefresh,
                            titleVisibility: .visible) {
            Button("Replace", role: .destructive) { startRefresh() }
            Button("Keep", role: .cancel) {}
        }
    }

    /// The references the entry would be fetched for, live as the user types. Hidden when there are none.
    @ViewBuilder
    private var linkedLine: some View {
        let detected = liveReferences
        if !detected.linkedLine.isEmpty {
            LabeledContent("Linked") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(detected.linkedLine).textSelection(.enabled)
                    if detected.overflowed {
                        Text(ContextCoordinator.overflowMessage).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The editable summary, the references it was built from, and Refresh.
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Context").font(.headline)
            TextEditor(text: $summary)
                .font(.body)
                .frame(minHeight: 60, idealHeight: 100)
                .border(.separator)
                .accessibilityLabel("Context summary")
            HStack(alignment: .firstTextBaseline) {
                if let refs = entry?.contextRefs, !refs.isEmpty {
                    Text("From \(refs.joined(separator: " · "))").foregroundStyle(.secondary)
                }
                if let id = entry?.id, let status = coordinator.status[id] {
                    Text(status.text).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", action: requestRefresh)
                    .disabled(!canRefresh)
                    .help(canRefresh ? "Fetch the saved references again and rewrite the summary."
                                     : "Save references and connect Jira or GitHub in Settings › Integrations.")
            }
            .font(.callout)
        }
    }

    /// Hints at the ticket the compiler would find in the text when the field is left blank.
    private var ticketPrompt: String {
        if let found = TicketDetector.firstTicket(in: text, pattern: store.settings.template.ticketPattern) {
            return "Found in text: \(found)"
        }
        return "e.g. ABC-123"
    }

    private var isTextBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard !isTextBlank else { return }
        let ticket = Self.optional(ticketRef)
        let hint = Self.optional(durationHint)
        let saved: LogEntry
        if let entry {
            entry.type = type
            entry.ticketRef = ticket
            entry.durationHint = hint
            entry.text = text
            if DayKey.string(for: day) != DayKey.string(for: initialDay) { entry.move(to: day) }
            saved = entry
        } else {
            saved = LogEntry(day: day, type: type, ticketRef: ticket, durationHint: hint, text: text)
            context.insert(saved)
        }
        // Only a change typed here marks the summary edited; a fetched summary never does.
        if summary != loadedSummary {
            saved.contextSummary = Self.optional(summary) == nil ? nil : summary
            saved.contextEdited = true
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            saveError = "Could not save: \(error.localizedDescription)"
            return
        }
        applyContextPolicy(to: saved)
    }

    /// After the entry is saved: fetch, clear or ask. Stored refs change only when a summary is applied,
    /// so they always name what the summary was built from; an older in-flight job sees the new refs and is dropped.
    private func applyContextPolicy(to saved: LogEntry) {
        let current = coordinator.detect(saved).canonical
        let action = ContextPolicy.onSave(
            current: current, stored: saved.contextRefs,
            hasSummary: Self.optional(saved.contextSummary ?? "") != nil, edited: saved.contextEdited)
        switch action {
        case .fetch:
            coordinator.enqueue(saved)
        case .clear:
            coordinator.clear(saved)
        case .confirmReplace:
            pendingReplace = PendingReplace(entry: saved)
            confirmingReplace = true
            return
        case .none:
            break
        }
        dismiss()
    }

    private func finishReplace(_ pending: PendingReplace, replace: Bool) {
        pendingReplace = nil
        if replace { coordinator.enqueue(pending.entry) }
        dismiss()
    }

    // MARK: - Refresh

    /// Refresh fetches the saved entry's references, which is what the coordinator reads.
    private var canRefresh: Bool {
        guard let entry, coordinator.isAnyConnected else { return false }
        return !coordinator.detect(entry).references.isEmpty
    }

    /// Confirms only when a non-blank summary the user edited (saved or typed here) would be replaced.
    private func requestRefresh() {
        guard let entry else { return }
        let edited = entry.contextEdited || summary != loadedSummary
        let hasSummary = Self.optional(summary) != nil
        switch ContextPolicy.onRefresh(current: coordinator.detect(entry).canonical, hasSummary: hasSummary, edited: edited) {
        case .fetch: startRefresh()
        case .confirmReplace: confirmingRefresh = true
        case .none, .clear: break
        }
    }

    /// Drops any unsaved summary edit, so the new summary shows here when it arrives.
    private func startRefresh() {
        guard let entry else { return }
        summary = loadedSummary
        coordinator.enqueue(entry)
    }

    // MARK: - References

    private var liveReferences: DetectedReferences {
        ReferenceDetector.detect(ticketRef: Self.optional(ticketRef), text: text,
                                 ticketPattern: store.settings.template.ticketPattern,
                                 defaultRepo: store.settings.integrations.defaultRepo)
    }

    /// Reads a `yyyy-MM-dd` day key as that date in the current time zone; nil if it doesn't parse.
    /// Built from components, so a day whose midnight falls in a DST gap still resolves.
    private static func date(forKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Blank optional fields are stored as nil, not as empty strings.
    private static func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
