import Foundation

/// JSON Schema for the compile reply, so constrained decoding can force one item per entry key.
public enum ResponseSchema {
    /// Prompt order. Constrained decoders keep property order, so `key` comes first and anchors the item.
    static let itemFields = ["key", "minutes", "fixedStart", "fixedEnd", "description",
                             "ticket", "activityType", "classification"]

    public static func json(keys: [String], activityTypes: [String], classifications: [String]) -> String {
        let items = keys.map { item(key: $0, activityTypes: activityTypes, classifications: classifications) }
        return object([
            ("additionalProperties", fragment(false)),
            ("properties", object([
                ("items", object([
                    ("items", fragment(false)),
                    ("maxItems", fragment(keys.count)),
                    ("minItems", fragment(keys.count)),
                    ("prefixItems", "[" + items.joined(separator: ",") + "]"),
                    ("type", fragment("array")),
                ])),
            ])),
            ("required", fragment(["items"])),
            ("type", fragment("object")),
        ])
    }

    private static func item(key: String, activityTypes: [String], classifications: [String]) -> String {
        let schemas: [String: Any] = [
            "key": ["const": key],
            "minutes": ["type": "integer", "minimum": 1] as [String: Any],
            "fixedStart": nullableString,
            "fixedEnd": nullableString,
            "description": ["type": "string"],
            "ticket": nullableString,
            "activityType": oneOf(activityTypes),
            "classification": oneOf(classifications),
        ]
        return object([
            ("additionalProperties", fragment(false)),
            ("properties", object(itemFields.map { ($0, fragment(schemas[$0]!)) })),
            ("required", fragment(itemFields)),
            ("type", fragment("object")),
        ])
    }

    private static var nullableString: [String: Any] { ["anyOf": [["type": "string"], ["type": "null"]]] }

    /// Exact strings, since the validator compares them verbatim; an empty list cannot be an
    /// empty enum (nothing would match), so it falls back to any string for the validator to flag.
    private static func oneOf(_ values: [String]) -> [String: Any] {
        var seen = Set<String>()
        let unique = values.filter { seen.insert($0).inserted }
        return unique.isEmpty ? ["type": "string"] : ["enum": unique]
    }

    /// Joins already-encoded values in the given order; names are escaped like any other string.
    private static func object(_ members: [(name: String, json: String)]) -> String {
        "{" + members.map { fragment($0.name) + ":" + $0.json }.joined(separator: ",") + "}"
    }

    /// Only strings, numbers, bools, arrays and dictionaries go in, so serialization cannot fail.
    private static func fragment(_ value: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }
}
