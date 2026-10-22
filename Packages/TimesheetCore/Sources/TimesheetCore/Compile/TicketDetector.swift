import Foundation

/// Finds a ticket reference in free text with the user's ticket pattern.
/// Deterministic, so it beats the model, which can miss or invent tickets.
public enum TicketDetector {
    /// First non-empty match of `pattern` in `text`; nil for an empty or invalid pattern.
    public static func firstTicket(in text: String, pattern: String) -> String? {
        guard !pattern.isEmpty, let regex = try? Regex(pattern),
              let match = text.firstMatch(of: regex), !match.output.isEmpty else { return nil }
        return String(text[match.range])
    }
}
