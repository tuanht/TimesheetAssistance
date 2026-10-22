import Foundation

/// The references found in one entry, de-duplicated and capped.
public struct DetectedReferences: Equatable, Sendable {
    public var references: [ContextReference]
    /// True when more distinct references were found than `ReferenceDetector.maxReferences`.
    public var overflowed: Bool

    public init(references: [ContextReference], overflowed: Bool) {
        self.references = references
        self.overflowed = overflowed
    }

    public var canonical: [String] { references.map(\.canonical) }

    /// Canonical references joined by " · "; empty when there are none.
    public var linkedLine: String { canonical.joined(separator: " · ") }
}

/// Finds Jira keys and GitHub pull requests in an entry's ticket field and text.
public enum ReferenceDetector {
    public static let maxReferences = 5

    public static func detect(ticketRef: String?, text: String, ticketPattern: String,
                              defaultRepo: String?) -> DetectedReferences {
        var found: [ContextReference] = []
        if let key = fieldKey(ticketRef, pattern: ticketPattern) { found.append(.jira(key: key)) }
        found += textReferences(in: text, pattern: ticketPattern, defaultRepo: defaultRepo)

        var seen = Set<String>()
        let unique = found.filter { seen.insert($0.canonical).inserted }
        return DetectedReferences(references: Array(unique.prefix(maxReferences)),
                                  overflowed: unique.count > maxReferences)
    }

    /// The trimmed ticket field when the whole of it matches the pattern.
    private static func fieldKey(_ ticketRef: String?, pattern: String) -> String? {
        guard let ref = ticketRef?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty,
              TicketDetector.tickets(in: ref, pattern: pattern).contains(ref) else { return nil }
        return ref
    }

    /// PRs and Jira keys in order of position. PR spans are found first and masked,
    /// so a key inside a PR URL or a qualified PR counted as bare is never reported twice.
    private static func textReferences(in text: String, pattern: String,
                                       defaultRepo: String?) -> [ContextReference] {
        let source = text as NSString
        var masked = text
        var spans: [(range: NSRange, reference: ContextReference)] = []

        for pass in prPasses(defaultRepo: defaultRepo) {
            for match in pass.regex.matches(in: masked, range: NSRange(location: 0, length: (masked as NSString).length)) {
                guard let reference = pass.build(match, source) else { continue }
                spans.append((match.range, reference))
            }
            masked = mask(masked, ranges: spans.map(\.range))
        }
        spans.sort { $0.range.location < $1.range.location }

        // Jira keys come from the masked gaps between PR spans, which keeps position order.
        let maskedSource = masked as NSString
        var result: [ContextReference] = []
        var cursor = 0
        for span in spans {
            result += jiraKeys(in: maskedSource.substring(with: NSRange(location: cursor, length: span.range.location - cursor)), pattern: pattern)
            result.append(span.reference)
            cursor = NSMaxRange(span.range)
        }
        result += jiraKeys(in: maskedSource.substring(from: cursor), pattern: pattern)
        return result
    }

    private struct PRPass {
        let regex: NSRegularExpression
        let build: (NSTextCheckingResult, NSString) -> ContextReference?
    }

    private static let urlRegex = regex(#"https?://github\.com/([A-Za-z0-9-]+)/([A-Za-z0-9._-]+)/pull/(\d+)\S*"#)
    private static let qualifiedRegex = regex(#"(?<![\w/.])([A-Za-z0-9-]+)/([A-Za-z0-9._-]+)#(\d+)\b"#)
    private static let bareRegex = regex(#"(?<![\w/#])#(\d+)\b"#)
    private static let repoRegex = regex(#"^([A-Za-z0-9-]+)/([A-Za-z0-9._-]+)$"#)

    private static func prPasses(defaultRepo: String?) -> [PRPass] {
        let qualified: (NSTextCheckingResult, NSString) -> ContextReference? = { match, source in
            pullRequest(owner: source.substring(with: match.range(at: 1)),
                        repo: source.substring(with: match.range(at: 2)),
                        number: source.substring(with: match.range(at: 3)))
        }
        var passes = [PRPass(regex: urlRegex, build: qualified), PRPass(regex: qualifiedRegex, build: qualified)]
        if let (owner, repo) = parseRepo(defaultRepo) {
            passes.append(PRPass(regex: bareRegex) { match, source in
                pullRequest(owner: owner, repo: repo, number: source.substring(with: match.range(at: 1)))
            })
        }
        return passes
    }

    private static func pullRequest(owner: String, repo: String, number: String) -> ContextReference? {
        guard let value = Int(number) else { return nil }
        return .pullRequest(owner: owner, repo: repo, number: value)
    }

    /// `owner/repo` split in two; nil when blank or malformed.
    private static func parseRepo(_ value: String?) -> (String, String)? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let source = value as NSString
        guard let match = repoRegex.firstMatch(in: value, range: NSRange(location: 0, length: source.length)) else { return nil }
        return (source.substring(with: match.range(at: 1)), source.substring(with: match.range(at: 2)))
    }

    private static func jiraKeys(in text: String, pattern: String) -> [ContextReference] {
        TicketDetector.tickets(in: text, pattern: pattern).map { .jira(key: $0) }
    }

    /// Replaces each range with spaces of the same UTF-16 length, so positions stay valid.
    private static func mask(_ text: String, ranges: [NSRange]) -> String {
        let result = NSMutableString(string: text)
        for range in ranges {
            result.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        return result as String
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Constant patterns; a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern)
    }
}
