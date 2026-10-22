import Foundation

public struct ModelItem: Decodable, Equatable, Sendable {
    public var key: String
    public var minutes: Int
    public var fixedStart: String?
    public var fixedEnd: String?
    public var description: String
    public var ticket: String?
    public var activityType: String
    public var classification: String

    public init(
        key: String, minutes: Int, fixedStart: String?, fixedEnd: String?,
        description: String, ticket: String?, activityType: String, classification: String
    ) {
        self.key = key
        self.minutes = minutes
        self.fixedStart = fixedStart
        self.fixedEnd = fixedEnd
        self.description = description
        self.ticket = ticket
        self.activityType = activityType
        self.classification = classification
    }

    private enum CodingKeys: String, CodingKey {
        case key, minutes, fixedStart, fixedEnd, description, ticket, activityType, classification
    }

    /// Small models often emit null or omit fields; keep the item and let validation flag the gaps.
    /// Throws only when `key` is missing or empty, since the item cannot be matched to an entry.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let key = (try? c.decodeIfPresent(String.self, forKey: .key)) ?? nil
        guard let key, !key.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Item has no usable key"))
        }
        func string(_ k: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil }
        self.key = key
        minutes = ((try? c.decodeIfPresent(Int.self, forKey: .minutes)) ?? nil) ?? ModelItem.defaultMinutes
        fixedStart = string(.fixedStart)
        fixedEnd = string(.fixedEnd)
        description = string(.description) ?? ""
        ticket = string(.ticket)
        activityType = string(.activityType) ?? ""
        classification = string(.classification) ?? ""
    }

    static let defaultMinutes = 30
}

public enum ParseError: Error, Equatable {
    case noJSON
    case invalidJSON(String)
}

public enum ResponseParser {
    private struct Envelope: Decodable {
        var items: [ModelItem]

        private enum CodingKeys: String, CodingKey { case items }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decode([DroppableItem].self, forKey: .items).compactMap(\.item)
        }
    }

    /// One malformed item (no key, not an object) is dropped instead of failing the whole response.
    private struct DroppableItem: Decodable {
        var item: ModelItem?

        init(from decoder: Decoder) throws {
            item = try? ModelItem(from: decoder)
        }
    }

    public static func parse(_ text: String) throws -> [ModelItem] {
        let cleaned = strippingThinkBlocks(text)
        let candidates = fencedBlocks(in: cleaned) + balancedObjects(in: cleaned)
        guard !candidates.isEmpty else {
            if cleaned.contains("{") { throw ParseError.invalidJSON("Unbalanced braces: response looks truncated") }
            throw ParseError.noJSON
        }
        var lastError = "No candidate decoded"
        for candidate in candidates {
            do {
                return try JSONDecoder().decode(Envelope.self, from: Data(candidate.utf8)).items
            } catch {
                lastError = String(describing: error)
            }
        }
        throw ParseError.invalidJSON(lastError)
    }

    /// Reasoning models (e.g. Qwen3) emit `<think>…</think>` that may itself contain braces.
    static func strippingThinkBlocks(_ text: String) -> String {
        text.replacing(/(?s)<think>.*?<\/think>/, with: "")
    }

    static func fencedBlocks(in text: String) -> [String] {
        text.matches(of: /(?s)```[A-Za-z]*[ \t]*\n?(.*?)```/)
            .map { String($0.output.1).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Top-level balanced `{…}` spans, skipping braces inside JSON strings.
    static func balancedObjects(in text: String) -> [String] {
        var results: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else if ch == "\"" && depth > 0 {
                inString = true
            } else if ch == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if ch == "}" && depth > 0 {
                depth -= 1
                if depth == 0, let s = start {
                    results.append(String(text[s...index]))
                    start = nil
                }
            }
            index = text.index(after: index)
        }
        return results
    }
}
