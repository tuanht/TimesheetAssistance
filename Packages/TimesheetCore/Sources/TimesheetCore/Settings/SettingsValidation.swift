import Foundation

/// A reason a settings value was rejected, phrased for display next to the field.
public struct ValidationMessage: Error, Equatable, Sendable {
    public var text: String

    public init(_ text: String) {
        self.text = text
    }
}

/// Checks applied before a settings edit is saved; an invalid value is never saved.
public enum SettingsValidation {
    public static let roundingOptions = [5, 10, 15, 30]

    // MARK: Template

    public static func separatorError(_ separator: String) -> String? {
        isBlank(separator) ? "The separator can't be blank." : nil
    }

    public static func formatError(_ format: String) -> String? {
        isBlank(format) ? "The format can't be blank." : nil
    }

    public static func ticketPatternError(_ pattern: String) -> String? {
        if isBlank(pattern) { return "The ticket pattern can't be blank." }
        do {
            _ = try Regex(pattern)
            return nil
        } catch {
            return "Not a valid regular expression."
        }
    }

    public static func maxDescriptionLength(_ text: String) -> Result<Int, ValidationMessage> {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)), n > 0 else {
            return .failure(ValidationMessage("Enter a whole number greater than 0."))
        }
        return .success(n)
    }

    public static func fieldsError(_ fields: [TemplateField]) -> String? {
        fields.isEmpty ? "Turn on at least one field." : nil
    }

    // MARK: Lists

    /// One entry per value: nil if valid, else why. The first of a set of duplicates is kept valid.
    public static func listErrors(_ values: [String]) -> [String?] {
        var seen = Set<String>()
        return values.map { value in
            let key = listKey(value)
            if key.isEmpty { return "A value can't be blank." }
            if !seen.insert(key).inserted { return "“\(trimmed(value))” is already in the list." }
            return nil
        }
    }

    public static func newListValueError(_ value: String, existing: [String]) -> String? {
        let key = listKey(value)
        if key.isEmpty { return "A value can't be blank." }
        if existing.contains(where: { listKey($0) == key }) { return "“\(trimmed(value))” is already in the list." }
        return nil
    }

    // MARK: Working hours

    public static func clockTime(_ text: String) -> Result<ClockTime, ValidationMessage> {
        guard let t = ClockTime(text.trimmingCharacters(in: .whitespaces)) else {
            return .failure(ValidationMessage("Use HH:mm, e.g. 09:00."))
        }
        return .success(t)
    }

    public static func workingHoursError(_ hours: WorkingHours) -> String? {
        if hours.end <= hours.start { return "The day must end after it starts." }
        if hours.lunchEnd < hours.lunchStart { return "Lunch must end at or after it starts." }
        if hours.lunchStart < hours.start || hours.lunchEnd > hours.end {
            return "Lunch must lie within the working day."
        }
        if !roundingOptions.contains(hours.roundingMinutes) {
            return "Rounding must be 5, 10, 15 or 30 minutes."
        }
        return nil
    }

    // MARK: Helpers

    private static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func listKey(_ s: String) -> String {
        trimmed(s).lowercased()
    }
}
