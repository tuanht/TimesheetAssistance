import SwiftData
import SwiftUI
import TimesheetCore

/// Sheet that creates a new entry on the picked day, or edits `entry` in place.
struct EntryEditor: View {
    let entry: LogEntry?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SettingsStore
    @State private var day: Date
    @State private var type: EntryType
    @State private var ticketRef: String
    @State private var durationHint: String
    @State private var text: String
    @State private var saveError: String?

    /// A new entry starts on `defaultDay`; an existing one on the day of its `dayKey`.
    init(defaultDay: Date, entry: LogEntry?) {
        self.entry = entry
        _day = State(initialValue: entry.flatMap { Self.date(forKey: $0.dayKey) } ?? defaultDay)
        _type = State(initialValue: entry?.type ?? .ticket)
        _ticketRef = State(initialValue: entry?.ticketRef ?? "")
        _durationHint = State(initialValue: entry?.durationHint ?? "")
        _text = State(initialValue: entry?.text ?? "")
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
                TextField("Duration hint", text: $durationHint, prompt: Text("e.g. ~2h"))
            }
            Text("Text").font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 220)
                .border(.separator)
                .accessibilityLabel("Entry text")
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
        .frame(minWidth: 520, idealWidth: 600, minHeight: 440)
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
        if let entry {
            entry.type = type
            entry.ticketRef = ticket
            entry.durationHint = hint
            entry.text = text
            if entry.dayKey != DayKey.string(for: day) { entry.move(to: day) }
        } else {
            context.insert(LogEntry(day: day, type: type, ticketRef: ticket, durationHint: hint, text: text))
        }
        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            saveError = "Could not save: \(error.localizedDescription)"
        }
    }

    /// Reads a `yyyy-MM-dd` day key as that date in the current time zone; nil if it doesn't parse.
    private static func date(forKey key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    /// Blank optional fields are stored as nil, not as empty strings.
    private static func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
