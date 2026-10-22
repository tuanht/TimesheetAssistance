import LocalModels
import SwiftData
import SwiftUI
import TimesheetCore

/// Pick a day, compile its entries with the configured model, fix the lines, copy them.
struct CompileView: View {
    @Binding var day: Date

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var models: MLXModelManager

    var body: some View {
        VStack(spacing: 0) {
            DayBar(day: $day)
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            // Rebuilt per day so the view model loads that day's entries and saved result.
            CompileDayView(model: CompileViewModel(day: day, context: context, settings: settings, models: models))
                .id(DayKey.string(for: day))
        }
        .navigationTitle("Compile")
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
                    if model.lines.isEmpty && model.state != .running {
                        ContentUnavailableView("No compiled lines", systemImage: "list.bullet.rectangle",
                                               description: Text("Compile the day to get timesheet lines."))
                    }
                }
            Divider()
            footer
                .padding()
        }
        .onAppear(perform: model.load)
        .onDisappear(perform: model.cancel)
        .onChange(of: settings.settings) { model.revalidate() }
        .confirmationDialog("Replace the saved result for this day?", isPresented: $confirmingReplace,
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
                let differs = model.totalMinutes != model.workingMinutes
                Label(TotalText.total(model.totalMinutes, of: model.workingMinutes),
                      systemImage: differs ? "exclamationmark.triangle" : "clock")
                    .foregroundStyle(differs ? .orange : .secondary)
                    .help(differs ? "The lines don’t add up to the working day." : "")
                Spacer()
                if copiedToken != nil {
                    Text("Copied").foregroundStyle(.secondary)
                }
                Button("Copy day", systemImage: "doc.on.doc", action: copy)
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
        if model.hasSavedResult { confirmingReplace = true } else { model.start() }
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
            if model.state == .running {
                ProgressView().controlSize(.small)
                Text("Compiling…").foregroundStyle(.secondary)
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
                    Text("No entries for this day").foregroundStyle(.secondary)
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

    var body: some View {
        Table(model.lines) {
            TableColumn("") { line in
                let messages = IssueMessages.rowMessages(
                    for: line.id, issues: model.issues, lines: model.lines, settings: settings.settings)
                if !messages.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(messages.joined(separator: "\n"))
                        .accessibilityLabel(messages.joined(separator: " "))
                }
            }
            .width(20)
            TableColumn("Start") { line in
                timeField(line.start) { time in model.edit(line.id) { $0.start = time } }
            }
            .width(min: 56, ideal: 60)
            TableColumn("End") { line in
                timeField(line.end) { time in model.edit(line.id) { $0.end = time } }
            }
            .width(min: 56, ideal: 60)
            TableColumn("Description") { line in
                CommitField(value: line.description, prompt: "Description") { text in
                    model.edit(line.id) { $0.description = text }
                }
            }
            .width(min: 160, ideal: 280)
            TableColumn("Ticket") { line in
                CommitField(value: line.ticket ?? "", prompt: "None") { text in
                    model.edit(line.id) { $0.ticket = LineEditing.ticket(from: text) }
                }
            }
            .width(min: 70, ideal: 90)
            TableColumn("Activity type") { line in
                ChoicePicker(label: "Activity type", list: settings.settings.activityTypes,
                             current: line.activityType) { value in
                    model.edit(line.id) { $0.activityType = value }
                }
            }
            .width(min: 110, ideal: 130)
            TableColumn("Classification") { line in
                ChoicePicker(label: "Classification", list: settings.settings.classifications,
                             current: line.classification) { value in
                    model.edit(line.id) { $0.classification = value }
                }
            }
            .width(min: 110, ideal: 130)
        }
    }

    private func timeField(_ time: ClockTime, commit: @escaping (ClockTime) -> Void) -> some View {
        CommitField(value: time.hhmm, prompt: "HH:mm", isValid: { LineEditing.time(from: $0) != nil }) { text in
            if let parsed = LineEditing.time(from: text) { commit(parsed) }
        }
        .font(.body.monospacedDigit())
    }
}

/// A text field that applies its text on Return or when it loses focus, and only when valid.
private struct CommitField: View {
    let value: String
    let prompt: String
    var isValid: (String) -> Bool = { _ in true }
    let commit: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let valid = isValid(text)
        TextField(prompt, text: $text, prompt: Text(prompt))
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
