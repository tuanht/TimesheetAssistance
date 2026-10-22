import Foundation

/// Finds a ticket reference in free text with the user's ticket pattern.
/// Deterministic, so it beats the model, which can miss or invent tickets.
public enum TicketDetector {
    /// First match of `pattern` in `text`, trimmed; nil for an empty or invalid pattern or a blank match.
    public static func firstTicket(in text: String, pattern: String) -> String? {
        guard !pattern.isEmpty, let regex = try? Regex(pattern),
              let match = text.firstMatch(of: regex) else { return nil }
        let ticket = text[match.range].trimmingCharacters(in: .whitespacesAndNewlines)
        return ticket.isEmpty ? nil : ticket
    }
}
