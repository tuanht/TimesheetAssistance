import SwiftData
import SwiftUI
import TimesheetCore

/// The private work log for a day, week or month: pick a period, then add, edit and delete its entries.
struct DailyLogView: View {
    @Binding var anchor: Date
    @Binding var kind: PeriodKind

    var body: some View {
        let range = Period.range(kind, containing: anchor)
        VStack(spacing: 0) {
            PeriodBar(anchor: $anchor, kind: $kind)
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            // Rebuilt per period so its @Query predicate matches the selected days.
            EntryList(anchor: anchor, kind: kind, range: range)
                .id(range.keys().joined(separator: ",") + kind.rawValue)
        }
        .navigationTitle("Daily log")
    }
}

/// What the editor sheet is open for.
private enum EditorTarget: Identifiable {
    case new
    case edit(LogEntry)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let entry): entry.id.uuidString
        }
    }
}

private struct EntryList: View {
    let anchor: Date
    let kind: PeriodKind
    let range: DayRange

    @Environment(\.modelContext) private var context
    @Query private var entries: [LogEntry]
    @State private var selection: LogEntry.ID?
    @State private var editor: EditorTarget?
    @State private var pendingDelete: LogEntry?
    @State private var deleteError: String?

    init(anchor: Date, kind: PeriodKind, range: DayRange) {
        self.anchor = anchor
        self.kind = kind
        self.range = range
        let keys = range.keys()
        _entries = Query(filter: #Predicate<LogEntry> { keys.contains($0.dayKey) },
                         sort: [SortDescriptor(\.dayKey), SortDescriptor(\.createdAt)])
    }

    var body: some View {
        List(selection: $selection) {
            if kind == .day {
                ForEach(entries) { EntryRow(entry: $0) }
            } else {
                ForEach(daysWithEntries, id: \.key) { day in
                    Section(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                        ForEach(day.entries) { EntryRow(entry: $0) }
                    }
                }
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "square.and.pencil",
                                       description: Text("Press ⌘N to log work for this \(unit)."))
            }
        }
        .contextMenu(forSelectionType: LogEntry.ID.self) { ids in
            if let entry = entry(for: ids.first) {
                Button("Edit") { editor = .edit(entry) }
                Button("Delete", role: .destructive) { pendingDelete = entry }
            }
        } primaryAction: { ids in
            // Double-click or Return.
            if let entry = entry(for: ids.first) { editor = .edit(entry) }
        }
        .onDeleteCommand {
            if let entry = entry(for: selection) { pendingDelete = entry }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { editor = .new } label: { Label("New Entry", systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("New entry (⌘N)")
                Button { if let entry = entry(for: selection) { editor = .edit(entry) } } label: {
                    Label("Edit Entry", systemImage: "pencil")
                }
                .disabled(selection == nil)
                .help("Edit entry (Return)")
                Button { if let entry = entry(for: selection) { pendingDelete = entry } } label: {
                    Label("Delete Entry", systemImage: "trash")
                }
                .disabled(selection == nil)
                .help("Delete entry (⌫)")
            }
        }
        .sheet(item: $editor) { target in
            switch target {
            case .new: EntryEditor(defaultDay: newEntryDay, entry: nil)
            case .edit(let entry): EntryEditor(defaultDay: newEntryDay, entry: entry)
            }
        }
        .confirmationDialog(deleteTitle, isPresented: isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Could not delete the entry", isPresented: isShowingDeleteError) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var unit: String { kind.displayName.lowercased() }

    /// Day mode keeps its original wording.
    private var emptyTitle: String { kind == .day ? "No entries" : "No entries this \(unit)" }

    /// The anchor day when it is in range, else the first day of the range.
    private var newEntryDay: Date {
        range.keys().contains(DayKey.string(for: anchor)) ? anchor : range.start
    }

    /// Days of the range that have entries, oldest first, each with its entries in `entries` order.
    private var daysWithEntries: [(key: String, date: Date, entries: [LogEntry])] {
        let byKey = Dictionary(grouping: entries, by: \.dayKey)
        return zip(range.keys(), range.days()).compactMap { key, date in
            byKey[key].map { (key: key, date: date, entries: $0) }
        }
    }

    private func entry(for id: LogEntry.ID?) -> LogEntry? {
        guard let id else { return nil }
        return entries.first { $0.id == id }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var isShowingDeleteError: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    private var deleteTitle: String {
        guard let entry = pendingDelete else { return "Delete entry?" }
        let preview = Self.firstWords(of: entry.text)
        return preview.isEmpty
            ? "Delete \(entry.type.displayName) entry?"
            : "Delete \(entry.type.displayName) entry “\(preview)”?"
    }

    private func confirmDelete() {
        guard let entry = pendingDelete else { return }
        pendingDelete = nil
        if selection == entry.id { selection = nil }
        context.delete(entry)
        do {
            try context.save()
        } catch {
            context.rollback()
            deleteError = error.localizedDescription
        }
    }

    static func firstWords(of text: String, count: Int = 6) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        let head = words.prefix(count).joined(separator: " ")
        return words.count > count ? head + "…" : head
    }
}

private struct EntryRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(entry.type.displayName).font(.headline)
                if let ticket = entry.ticketRef {
                    Text(ticket).font(.body.monospaced()).foregroundStyle(.secondary)
                }
                if let hint = entry.durationHint {
                    Text(hint).foregroundStyle(.secondary)
                }
            }
            Text(firstTwoLines)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var firstTwoLines: String {
        entry.text.split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(2).joined(separator: "\n")
    }
}
