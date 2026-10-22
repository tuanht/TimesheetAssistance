import SwiftUI
import TimesheetCore

/// The two user-editable value lists that compiled lines must use.
struct ListsTab: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            EditableList(title: "Activity types", keyPath: \.activityTypes)
            EditableList(title: "Classifications", keyPath: \.classifications)
        }
        .padding()
    }
}

/// Add, rename, delete and reorder one list. Saves only while every value is non-blank and unique.
private struct EditableList: View {
    let title: String
    let keyPath: WritableKeyPath<AppSettings, [String]>

    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var session: SettingsSession

    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var text: String
    }

    @State private var rows: [Row] = []
    @State private var loaded = false
    @State private var selection: Row.ID?
    @State private var newValue = ""
    @State private var addError: String?

    var body: some View {
        let errors = SettingsValidation.listErrors(rows.map(\.text))
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            List(selection: $selection) {
                ForEach(Array(zip($rows, errors)), id: \.0.id) { $row, error in
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Value", text: $row.text)
                            .labelsHidden()
                            .accessibilityLabel("\(title) value")
                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .tag(row.id)
                }
                .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { rows.remove(atOffsets: $0) }
            }
            .frame(minHeight: 260)
            HStack {
                Button { move(by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(!canMove(by: -1))
                    .accessibilityLabel("Move up")
                    .help("Move up")
                Button { move(by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(!canMove(by: 1))
                    .accessibilityLabel("Move down")
                    .help("Move down")
                Button { removeSelected() } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    .accessibilityLabel("Delete selected value")
                    .help("Delete selected value")
            }
            HStack {
                TextField("New value", text: $newValue)
                    .onSubmit(add)
                    .onChange(of: newValue) { addError = nil }
                Button("Add", action: add)
            }
            if let addError {
                Text(addError).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            rows = store.settings[keyPath: keyPath].map { Row(text: $0) }
        }
        .onChange(of: rows) { _, new in
            guard SettingsValidation.listErrors(new.map(\.text)).allSatisfy({ $0 == nil }) else { return }
            let values = new.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            if values != store.settings[keyPath: keyPath] {
                session.update { $0[keyPath: keyPath] = values }
            }
        }
    }

    private func add() {
        if let error = SettingsValidation.newListValueError(newValue, existing: rows.map(\.text)) {
            addError = error
            return
        }
        rows.append(Row(text: newValue.trimmingCharacters(in: .whitespacesAndNewlines)))
        newValue = ""
    }

    private func removeSelected() {
        guard let i = rows.firstIndex(where: { $0.id == selection }) else { return }
        rows.remove(at: i)
        selection = nil
    }

    private func canMove(by offset: Int) -> Bool {
        guard let i = rows.firstIndex(where: { $0.id == selection }) else { return false }
        return rows.indices.contains(i + offset)
    }

    private func move(by offset: Int) {
        guard let i = rows.firstIndex(where: { $0.id == selection }), rows.indices.contains(i + offset) else { return }
        rows.swapAt(i, i + offset)
    }
}
