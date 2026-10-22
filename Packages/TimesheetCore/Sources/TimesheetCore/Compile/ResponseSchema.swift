import Foundation

/// JSON Schema for the compile reply, so constrained decoding can force one item per entry key.
public enum ResponseSchema {
    public static func json(keys: [String], activityTypes: [String], classifications: [String]) -> String {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["items"],
            "properties": [
                "items": [
                    "type": "array",
                    "minItems": keys.count,
                    "maxItems": keys.count,
                    "items": false,
                    "prefixItems": keys.map { item(key: $0, activityTypes: activityTypes, classifications: classifications) },
                ] as [String: Any],
            ],
        ]
        // Only strings, numbers, bools, arrays and dictionaries go in, so serialization cannot fail.
        let data = try! JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func item(key: String, activityTypes: [String], classifications: [String]) -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["key", "minutes", "fixedStart", "fixedEnd", "description",
                         "ticket", "activityType", "classification"],
            "properties": [
                "key": ["const": key],
                "minutes": ["type": "integer", "minimum": 1] as [String: Any],
                "fixedStart": nullableString,
                "fixedEnd": nullableString,
                "description": ["type": "string"],
                "ticket": nullableString,
                "activityType": oneOf(activityTypes),
                "classification": oneOf(classifications),
            ] as [String: Any],
        ]
    }

    private static var nullableString: [String: Any] { ["anyOf": [["type": "string"], ["type": "null"]]] }

    /// Exact strings, since the validator compares them verbatim; an empty list cannot be an
    /// empty enum (nothing would match), so it falls back to any string for the validator to flag.
    private static func oneOf(_ values: [String]) -> [String: Any] {
        var seen = Set<String>()
        let unique = values.filter { seen.insert($0).inserted }
        return unique.isEmpty ? ["type": "string"] : ["enum": unique]
    }
}
