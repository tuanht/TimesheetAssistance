import SwiftUI
import TimesheetCore

/// Every template field as a chip: click turns it on or off, drag or ←/→ reorders it.
/// The chips that are on, in order, are the template's fields.
struct FieldChipsEditor: View {
    let commit: ([TemplateField]) -> Void

    private struct Row: Equatable {
        var field: TemplateField
        var isOn: Bool
    }

    @State private var rows: [Row]
    @State private var error: String?
    @State private var dropTarget: TemplateField?

    init(saved: [TemplateField], commit: @escaping ([TemplateField]) -> Void) {
        self.commit = commit
        let off = TemplateField.allCases.filter { !saved.contains($0) }
        _rows = State(initialValue: saved.map { Row(field: $0, isOn: true) } + off.map { Row(field: $0, isOn: false) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout {
                ForEach(rows, id: \.field) { row in
                    FieldChip(title: Self.title(row.field), isOn: row.isOn, isDropTarget: dropTarget == row.field,
                              toggle: { toggle(row.field) }, move: { reorder(ListReorder.move(row.field, by: $0, in: fields)) })
                        .draggable(row.field.rawValue)
                        .dropDestination(for: String.self) { items, _ in
                            guard let dragged = items.first.flatMap(TemplateField.init(rawValue:)) else { return false }
                            reorder(ListReorder.move(dragged, onto: row.field, in: fields))
                            return true
                        } isTargeted: { targeted in
                            if targeted { dropTarget = row.field } else if dropTarget == row.field { dropTarget = nil }
                        }
                }
            }
            Text("Click a field to turn it on or off. Drag it, or use ← →, to reorder.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .onChange(of: rows) { _, new in
            let fields = new.filter(\.isOn).map(\.field)
            error = SettingsValidation.fieldsError(fields)
            if error == nil { commit(fields) }
        }
    }

    private var fields: [TemplateField] { rows.map(\.field) }

    private func toggle(_ field: TemplateField) {
        guard let i = rows.firstIndex(where: { $0.field == field }) else { return }
        rows[i].isOn.toggle()
    }

    private func reorder(_ order: [TemplateField]) {
        rows = order.compactMap { field in rows.first { $0.field == field } }
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

/// One field: filled with a checkmark when on, outlined when off, so the state doesn't rely on colour alone.
private struct FieldChip: View {
    let title: String
    let isOn: Bool
    let isDropTarget: Bool
    let toggle: () -> Void
    let move: (Int) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        chip
            .contentShape(Capsule())
            .onTapGesture(perform: toggle)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.space) { toggle(); return .handled }
            .onKeyPress(.leftArrow) { move(-1); return .handled }
            .onKeyPress(.rightArrow) { move(1); return .handled }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            .accessibilityAction { toggle() }
            .accessibilityAction(named: "Move left") { move(-1) }
            .accessibilityAction(named: "Move right") { move(1) }
            .help(isOn ? "In the line. Click to remove." : "Not in the line. Click to add.")
    }

    private var chip: some View {
        Label(title, systemImage: isOn ? "checkmark" : "plus")
            .labelStyle(ChipLabelStyle())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .background(fill)
            .overlay(outline)
            .overlay(ring)
    }

    private var fill: some View {
        Capsule().fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
    }

    private var outline: some View {
        Capsule().strokeBorder(Color.secondary.opacity(isOn ? 0 : 0.5))
    }

    /// Shows keyboard focus and where a drop will land.
    private var ring: some View {
        Capsule()
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .padding(-3)
            .opacity(focused || isDropTarget ? 1 : 0)
    }
}

private struct ChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.caption.weight(.semibold))
            configuration.title
        }
    }
}
