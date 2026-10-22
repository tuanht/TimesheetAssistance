import Foundation

/// Finds ticket references in free text with the user's ticket pattern.
/// Deterministic, so it can check the model, which can miss or invent tickets.
public enum TicketDetector {
    /// Every non-blank match of `pattern` in `text`, trimmed, in order; empty for an empty or invalid pattern.
    public static func tickets(in text: String, pattern: String) -> [String] {
        guard !pattern.isEmpty, let regex = try? Regex(pattern) else { return [] }
        return text.matches(of: regex)
            .map { text[$0.range].trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// First non-blank match of `pattern` in `text`, trimmed; nil when there is none.
    public static func firstTicket(in text: String, pattern: String) -> String? {
        tickets(in: text, pattern: pattern).first
    }
}
