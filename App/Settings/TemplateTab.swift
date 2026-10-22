import SwiftUI
import TimesheetCore

/// Output line template: field order and visibility, separators, formats, ticket pattern, and a live sample.
struct TemplateTab: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var session: SettingsSession

    private var template: TemplateSettings { store.settings.template }

    var body: some View {
        Form {
            Section("Sample line") {
                Text(LineRenderer.render([Self.sampleLine], day: Date(), template: template))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Fields") {
                FieldOrderEditor(saved: template.fields) { fields in
                    session.update { $0.template.fields = fields }
                }
            }
            Section("Text") {
                ValidatedField("Separator", saved: template.separator,
                               validate: { v in
                                   // The pair must stay valid whichever side changes.
                                   SettingsValidation.separatorError(v)
                                       ?? SettingsValidation.separatorSubstituteError(
                                           template.separatorSubstitute, separator: v)
                                       .map { _ in "The separator substitute contains this separator." }
                               }) { v in
                    session.update { $0.template.separator = v }
                }
                ValidatedField("Separator substitute", saved: template.separatorSubstitute,
                               validate: { v in
                                   SettingsValidation.separatorSubstituteError(v, separator: template.separator)
                               }) { v in
                    session.update { $0.template.separatorSubstitute = v }
                }
                ValidatedField("Empty ticket placeholder", saved: template.emptyTicketPlaceholder,
                               validate: { _ in nil }) { v in
                    session.update { $0.template.emptyTicketPlaceholder = v }
                }
                ValidatedField("Date format", saved: template.dateFormat, prompt: "yyyy-MM-dd",
                               validate: SettingsValidation.formatError) { v in
                    session.update { $0.template.dateFormat = v }
                }
                ValidatedField("Time format", saved: template.timeFormat, prompt: "HH:mm",
                               validate: SettingsValidation.formatError) { v in
                    session.update { $0.template.timeFormat = v }
                }
                ValidatedField("Ticket pattern", saved: template.ticketPattern,
                               validate: SettingsValidation.ticketPatternError) { v in
                    session.update { $0.template.ticketPattern = v }
                }
            }
            Section("Description") {
                Toggle("Limit description length", isOn: limitBinding)
                if let max = template.maxDescriptionLength {
                    ValidatedField("Maximum characters", saved: String(max),
                                   validate: { text in
                                       if case .failure(let m) = SettingsValidation.maxDescriptionLength(text) { m.text } else { nil }
                                   }) { text in
                        if case .success(let n) = SettingsValidation.maxDescriptionLength(text) {
                            session.update { $0.template.maxDescriptionLength = n }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var limitBinding: Binding<Bool> {
        Binding(
            get: { template.maxDescriptionLength != nil },
            set: { on in session.update { $0.template.maxDescriptionLength = on ? Self.defaultMaxLength : nil } })
    }

    private static let defaultMaxLength = 80

    /// Fixed content so only the template changes what the sample shows.
    static let sampleLine = TimesheetLine(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        entryId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        start: ClockTime(9, 0), end: ClockTime(10, 30),
        description: "Fix login redirect | add regression test",
        ticket: "PROJ-123", activityType: "Development", classification: "Billable")
}

/// Every template field with an on/off toggle; the enabled ones, in list order, are the template's fields.
private struct FieldOrderEditor: View {
    let commit: ([TemplateField]) -> Void

    private struct Row: Equatable {
        var field: TemplateField
        var isOn: Bool
    }

    @State private var rows: [Row]
    @State private var error: String?

    init(saved: [TemplateField], commit: @escaping ([TemplateField]) -> Void) {
        self.commit = commit
        let off = TemplateField.allCases.filter { !saved.contains($0) }
        _rows = State(initialValue: saved.map { Row(field: $0, isOn: true) } + off.map { Row(field: $0, isOn: false) })
    }

    var body: some View {
        ForEach($rows, id: \.field) { $row in
            HStack {
                Toggle(Self.title(row.field), isOn: $row.isOn)
                Spacer()
                Button { move(row.field, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(rows.first?.field == row.field)
                    .accessibilityLabel("Move \(Self.title(row.field)) up")
                    .help("Move up")
                Button { move(row.field, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(rows.last?.field == row.field)
                    .accessibilityLabel("Move \(Self.title(row.field)) down")
                    .help("Move down")
            }
            .buttonStyle(.borderless)
        }
        .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
        .onChange(of: rows) { _, new in
            let fields = new.filter(\.isOn).map(\.field)
            error = SettingsValidation.fieldsError(fields)
            if error == nil { commit(fields) }
        }
        if let error {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    private func move(_ field: TemplateField, by offset: Int) {
        guard let i = rows.firstIndex(where: { $0.field == field }) else { return }
        let j = i + offset
        guard rows.indices.contains(j) else { return }
        rows.swapAt(i, j)
    }

    private static func title(_ field: TemplateField) -> String {
        switch field {
        case .date: "Date"
        case .start: "Start"
        case .end: "End"
        case .description: "Description"
        case .ticket: "Ticket"
        case .activityType: "Activity type"
        case .classification: "Classification"
        }
    }
}
