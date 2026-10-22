import LocalModels
import SwiftData
import SwiftUI
import TimesheetCore

/// What Compile works on: a period around the shared anchor, or a custom From–To range.
enum CompileRangeKind: String, CaseIterable {
    case day, week, month, custom

    var displayName: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .custom: "Custom"
        }
    }

    /// The matching period, or nil for a custom range.
    var period: PeriodKind? {
        switch self {
        case .day: .day
        case .week: .week
        case .month: .month
        case .custom: nil
        }
    }
}

/// Pick a day or range, compile its entries with the configured model, fix the lines, copy them.
struct CompileView: View {
    @Binding var anchor: Date
    @Binding var kind: CompileRangeKind
    @Binding var customStart: Date
    @Binding var customEnd: Date

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var models: MLXModelManager

    var body: some View {
        let range = self.range
        VStack(spacing: 0) {
            rangeBar
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            // Rebuilt per range so the view model loads those days' entries and saved results.
            CompileDayView(model: CompileViewModel(range: range, context: context, settings: settings, models: models))
                .id("\(DayKey.string(for: range.start))…\(DayKey.string(for: range.end))")
        }
        .navigationTitle("Compile")
    }

    private var range: DayRange {
        if let period = kind.period { return Period.range(period, containing: anchor) }
        return DayRange(from: customStart, to: customEnd)
    }

    /// Switching to Custom starts From–To on the period that was showing, not on today.
    /// Seeded before `kind` changes, so no stale custom range is loaded in between.
    private var kindSelection: Binding<CompileRangeKind> {
        Binding(get: { kind }, set: { newKind in
            if newKind == .custom, let period = kind.period {
                let shown = Period.range(period, containing: anchor)
                customStart = shown.start
                customEnd = shown.end
            }
            kind = newKind
        })
    }

    /// The period bar on the shared anchor, or From and To pickers; one Day|Week|Month|Custom picker either way.
    private var rangeBar: some View {
        HStack {
            if let period = kind.period {
                PeriodBar(anchor: $anchor, kind: .constant(period), showsKindPicker: false)
            } else {
                CalendarButton(title: Period.label(.day, anchor: customStart), date: $customStart,
                               accessibilityLabel: "From")
                Text("to").foregroundStyle(.secondary)
                CalendarButton(title: Period.label(.day, anchor: customEnd), date: $customEnd,
                               accessibilityLabel: "To")
                Spacer()
            }
            Picker("Range", selection: kindSelection) {
                ForEach(CompileRangeKind.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }
}

private struct CompileDayView: View {
    @StateObject private var model: CompileViewModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var models: MLXModelManager
    @State private var confirmingReplace = false
    @State private var copiedToken: UUID?

    init(model: @autoclosure @escaping () -> CompileViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        VStack(spacing: 0) {
            CompileBar(model: model, onCompile: requestCompile)
                .padding(.horizontal)
                .padding(.vertical, 8)
            messages
            Divider()
            LinesTable(model: model)
                .overlay {
                    if model.lines.isEmpty && !model.isRunning {
                        ContentUnavailableView("No compiled lines", systemImage: "list.bullet.rectangle",
                                               description: Text(model.isSingleDay
                                                   ? "Compile the day to get timesheet lines."
                                                   : "Compile the range to get timesheet lines."))
                    }
                }
            Divider()
            footer
                .padding()
        }
        .onAppear(perform: model.load)
        .onDisappear(perform: model.cancel)
        .onChange(of: settings.settings) { model.revalidate() }
        .confirmationDialog(replaceTitle, isPresented: $confirmingReplace,
                            titleVisibility: .visible) {
            Button("Replace", role: .destructive) { model.start() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your edits to the current lines will be lost.")
        }
    }

    @ViewBuilder
    private var messages: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .failed(let message) = model.state {
                HStack {
                    Label(message, systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Retry", action: requestCompile)
                        .disabled(!model.canCompile)
                }
            }
            if let summary = IssueMessages.missingLinesSummary(model.issues) {
                Label(summary, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if let storeError = model.storeError {
                Label(storeError, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                let differs = model.totalMinutes != model.expectedMinutes
                Label(TotalText.total(model.totalMinutes, of: model.expectedMinutes),
                      systemImage: differs ? "exclamationmark.triangle" : "clock")
                    .foregroundStyle(differs ? .orange : .secondary)
                    .help(differs ? (model.isSingleDay ? "The lines don’t add up to the working day."
                                                       : "The lines don’t add up to the working days.") : "")
                Spacer()
                if copiedToken != nil {
                    Text("Copied").foregroundStyle(.secondary)
                }
                Button(model.isSingleDay ? "Copy day" : "Copy range", systemImage: "doc.on.doc", action: copy)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.lines.isEmpty)
                    .help("Copy the lines as plain text (⌘⇧C)")
            }
            ScrollView([.vertical, .horizontal]) {
                Text(model.preview.isEmpty ? " " : model.preview)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 120)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Preview")
        }
    }

    /// Compile and Retry both ask before replacing a saved result, which may hold the user's edits.
    private func requestCompile() {
        if model.savedDaysToReplace > 0 { confirmingReplace = true } else { model.start() }
    }

    private var replaceTitle: String {
        if model.isSingleDay { return "Replace the saved result for this day?" }
        let count = model.savedDaysToReplace
        return count == 1 ? "Replace saved results for 1 day?" : "Replace saved results for \(count) days?"
    }

    private func copy() {
        model.copyToPasteboard()
        let token = UUID()
        copiedToken = token
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedToken == token { copiedToken = nil }
        }
    }
}

/// The Compile button, or the reason it can't run, or the running spinner with Cancel.
private struct CompileBar: View {
    @ObservedObject var model: CompileViewModel
    let onCompile: () -> Void
    // Observed so the client plan is re-read when the model setting or a download changes.
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var models: MLXModelManager
    @Environment(\.openSettings) private var openSettings
    @AppStorage("settingsTab") private var settingsTab = "template"

    var body: some View {
        let plan = model.clientPlan
        HStack(spacing: 12) {
            if case .running(let done, let total) = model.state {
                ProgressView().controlSize(.small)
                Text(model.isSingleDay ? "Compiling…" : "Compiling day \(done + 1) of \(total)…")
                    .foregroundStyle(.secondary)
                Button("Cancel") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Compile", action: onCompile)
                    .disabled(!model.canCompile)
                if case .unavailable(let reason) = plan {
                    Text(reason.message)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        settingsTab = "models"
                        openSettings()
                    }
                } else if model.entryCount == 0 {
                    Text(model.isSingleDay ? "No entries for this day" : "No entries in this range")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .font(.callout)
    }
}

/// The compiled lines; each cell edit is applied to its row in place and saved.
private struct LinesTable: View {
    @ObservedObject var model: CompileViewModel
    @EnvironmentObject private var settings: SettingsStore
    @State private var selection = Set<TimesheetLine.ID>()

    var body: some View {
        table
            .contextMenu(forSelectionType: TimesheetLine.ID.self) { ids in
                if !ids.isEmpty {
                    Button(ids.count == 1 ? "Delete line" : "Delete \(ids.count) lines", role: .destructive) {
                        delete(ids)
                    }
                }
            }
            .onDeleteCommand { delete(selection) }
    }

    private func delete(_ ids: Set<TimesheetLine.ID>) {
        selection.subtract(ids)
        model.delete(ids)
    }

    private var table: some View {
        Table(model.lines, selection: $selection) {
            TableColumn("") { row in
                let day = model.dayResult(containing: row.id)
                let messages = IssueMessages.rowMessages(
                    for: row.id, issues: day?.issues ?? [], lines: day?.lines ?? [], settings: settings.settings)
                if !messages.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(messages.joined(separator: "\n"))
                        .accessibilityLabel(messages.joined(separator: " "))
                }
            }
            .width(20)
            if !model.isSingleDay {
                TableColumn("Date") { row in
                    Text(Self.shortDate.string(from: row.day))
                        .monospacedDigit()
                }
                .width(min: 48, ideal: 56)
            }
            TableColumn("Start") { row in
                let line = row.line
                timeField(line.start) { time in model.edit(line.id) { $0.start = time } }
            }
            .width(min: 56, ideal: 60)
            TableColumn("End") { row in
                let line = row.line
                timeField(line.end) { time in model.edit(line.id) { $0.end = time } }
            }
            .width(min: 56, ideal: 60)
            TableColumn("Description") { row in
                let line = row.line
                CommitField(value: line.description, prompt: "Description", copyLabel: "Copy description") { text in
                    model.edit(line.id) { $0.description = text }
                }
            }
            .width(min: 160, ideal: 280)
            TableColumn("Ticket") { row in
                let line = row.line
                CommitField(value: line.ticket ?? "", prompt: "None", copyLabel: "Copy ticket") { text in
                    model.edit(line.id) { $0.ticket = LineEditing.ticket(from: text) }
                }
            }
            .width(min: 70, ideal: 90)
            TableColumn("Activity type") { row in
                let line = row.line
                ChoicePicker(label: "Activity type", list: settings.settings.activityTypes,
                             current: line.activityType) { value in
                    model.edit(line.id) { $0.activityType = value }
                }
            }
            .width(min: 110, ideal: 130)
            TableColumn("Classification") { row in
                let line = row.line
                ChoicePicker(label: "Classification", list: settings.settings.classifications,
                             current: line.classification) { value in
                    model.edit(line.id) { $0.classification = value }
                }
            }
            .width(min: 110, ideal: 130)
        }
    }

    /// Template-independent short date, e.g. "Oct 22".
    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private func timeField(_ time: ClockTime, commit: @escaping (ClockTime) -> Void) -> some View {
        CommitField(value: time.hhmm, prompt: "HH:mm", isValid: { LineEditing.time(from: $0) != nil }) { text in
            if let parsed = LineEditing.time(from: text) { commit(parsed) }
        }
        .font(.body.monospacedDigit())
    }
}

/// A text field that applies its text on Return or when it loses focus, and only when valid.
/// With a copy label it also shows a button that copies the text as shown, committed or not.
private struct CommitField: View {
    let value: String
    let prompt: String
    var isValid: (String) -> Bool = { _ in true }
    var copyLabel: String?
    let commit: (String) -> Void

    @State private var text = ""
    @State private var copiedToken: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            field
            if let copyLabel {
                Button(action: copy) {
                    Image(systemName: copiedToken == nil ? "doc.on.doc" : "checkmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(text.isEmpty)
                .help(copyLabel)
                .accessibilityLabel(copyLabel)
            }
        }
    }

    private var field: some View {
        let valid = isValid(text)
        return TextField(prompt, text: $text, prompt: Text(prompt))
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($focused)
            .foregroundStyle(valid ? Color.primary : Color.red)
            .help(valid ? "" : "Use HH:mm, for example 09:30.")
            .onAppear { text = value }
            .onChange(of: value) { text = value }
            .onSubmit(apply)
            .onChange(of: focused) { if !focused { apply() } }
    }

    private func apply() {
        guard isValid(text), text != value else { return }
        commit(text)
    }

    /// Copies without committing; the token keeps a quick second click from reverting the checkmark early.
    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let token = UUID()
        copiedToken = token
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedToken == token { copiedToken = nil }
        }
    }
}

/// A picker over a settings list; a value outside the list appears as an extra, highlighted option.
private struct ChoicePicker: View {
    let label: String
    let list: [String]
    let current: String
    let commit: (String) -> Void

    var body: some View {
        let options = LineEditing.choices(list: list, current: current)
        let isListed = options.first { $0.value == current }?.isListed ?? false
        Picker(label, selection: Binding(get: { current }, set: { if $0 != current { commit($0) } })) {
            ForEach(options, id: \.self) { option in
                Text(Self.title(option)).tag(option.value)
            }
        }
        .labelsHidden()
        .padding(.horizontal, 2)
        .background(isListed ? Color.clear : Color.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
        .help(isListed ? "" : "Not in the \(label.lowercased()) list in Settings.")
    }

    private static func title(_ option: ChoiceOption) -> String {
        guard !option.isListed else { return option.value }
        return option.value.isEmpty ? "⚠︎ None (not in list)" : "⚠︎ \(option.value) (not in list)"
    }
}
