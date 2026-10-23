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

    /// Only the empty string is rejected; whitespace such as a tab is a valid separator.
    public static func separatorError(_ separator: String) -> String? {
        separator.isEmpty ? "The separator can't be empty." : nil
    }

    /// Rejects a substitute that is empty, contains the separator, or contains the separator's
    /// non-empty core (trimmed of spaces and tabs). The renderer keeps the separator's padding
    /// around the substitute, so " | " with substitute "|" would still emit " | ".
    public static func separatorSubstituteError(_ substitute: String, separator: String) -> String? {
        if substitute.isEmpty { return "The separator substitute can't be empty." }
        let core = separator.trimmingCharacters(in: .whitespaces)
        if (!separator.isEmpty && substitute.contains(separator)) || (!core.isEmpty && substitute.contains(core)) {
            return "The separator substitute can't contain the separator."
        }
        return nil
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

    public static func listCountError(_ values: [String]) -> String? {
        values.isEmpty ? "The list must keep at least one value." : nil
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

    // MARK: Endpoint

    /// Parses the endpoint base URL. Remote endpoints must use https: App Transport Security
    /// blocks plain http to anything but local hosts.
    public static func endpointURL(_ text: String) -> Result<URL, ValidationMessage> {
        let text = trimmed(text)
        if text.isEmpty { return .failure(ValidationMessage("Enter a base URL.")) }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme)
        else { return .failure(ValidationMessage("Use a URL starting with http:// or https://.")) }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else {
            return .failure(ValidationMessage("The URL needs a host."))
        }
        // The base URL is stored in plain text in settings.json; credentials belong in the Keychain.
        if url.user(percentEncoded: false) != nil || url.password(percentEncoded: false) != nil {
            return .failure(ValidationMessage("Don't put credentials in the URL. Use the API key field."))
        }
        if scheme == "http", !EndpointPolicy.isLocal(url) {
            return .failure(ValidationMessage("Remote endpoints must use https."))
        }
        return .success(url)
    }

    public static func endpointModelError(_ model: String) -> String? {
        isBlank(model) ? "Enter a model name." : nil
    }

    /// A remote URL needs the user's confirmation unless the saved endpoint already has a
    /// confirmed URL on the same host.
    public static func needsRemoteConfirmation(_ url: URL, saved: ModelSelection) -> Bool {
        if EndpointPolicy.isLocal(url) { return false }
        guard case .endpoint(let config) = saved, config.remoteConfirmed else { return true }
        return config.baseURL.host(percentEncoded: false)?.lowercased() != url.host(percentEncoded: false)?.lowercased()
    }

    /// The API key a connection test may send. The stored Keychain key belongs to the saved
    /// endpoint's host, so it goes only to that host; a key the user typed goes wherever they test.
    public static func testConnectionKey(field: String, storedKey: String, url: URL, saved: ModelSelection) -> String? {
        if field.isEmpty { return nil }
        if field != storedKey { return field }
        guard case .endpoint(let config) = saved else { return nil }
        let sameHost = config.baseURL.host(percentEncoded: false)?.lowercased() == url.host(percentEncoded: false)?.lowercased()
        return sameHost ? field : nil
    }

    // MARK: Integrations

    /// An empty value means no default repository.
    public static func defaultRepoError(_ value: String) -> String? {
        if value.isEmpty { return nil }
        return value.wholeMatch(of: /[A-Za-z0-9-]+\/[A-Za-z0-9._-]+/) == nil
            ? "Use the form owner/repo, for example acme/web." : nil
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
