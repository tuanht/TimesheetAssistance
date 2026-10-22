import Foundation

/// Turns a compile error into text for the user; never includes raw model output.
public enum CompileFailure {
    /// `nil` for cancellation, which the user asked for and needs no message.
    public static func message(for error: Error) -> String? {
        switch error {
        case is CancellationError:
            return nil
        case let error as LLMError:
            return error.userMessage
        case is ParseError:
            return "The model's reply couldn't be read. Try again, or try another model."
        case CompileError.noEntries:
            return "No entries for this day."
        default:
            return "Compiling failed: \(error.localizedDescription)"
        }
    }
}
