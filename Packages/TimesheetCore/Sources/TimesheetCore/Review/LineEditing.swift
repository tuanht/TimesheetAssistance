import Foundation

/// One option of an activity type or classification picker.
public struct ChoiceOption: Equatable, Hashable, Sendable {
    public var value: String
    /// False for a value outside the settings list, shown so the user sees and replaces it.
    public var isListed: Bool

    public init(value: String, isListed: Bool) {
        self.value = value
        self.isListed = isListed
    }
}

/// Input handling for editing compiled lines.
public enum LineEditing {
    /// Strict `H:mm` or `HH:mm` with ASCII digits; surrounding whitespace is ignored.
    public static func time(from text: String) -> ClockTime? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.wholeMatch(of: /[0-9]{1,2}:[0-9]{2}/) != nil else { return nil }
        return ClockTime(trimmed)
    }

    /// Blank means no ticket.
    public static func ticket(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The settings list, plus the current value at the end when it isn't in the list.
    public static func choices(list: [String], current: String) -> [ChoiceOption] {
        var options = list.map { ChoiceOption(value: $0, isListed: true) }
        if !list.contains(current) {
            options.append(ChoiceOption(value: current, isListed: false))
        }
        return options
    }

    /// Swaps in the edited line by id; other rows keep their position, whatever the new times.
    public static func replacing(_ line: TimesheetLine, in lines: [TimesheetLine]) -> [TimesheetLine] {
        lines.map { $0.id == line.id ? line : $0 }
    }
}
