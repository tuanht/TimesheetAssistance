import Foundation
import Testing
@testable import TimesheetCore

struct ResponseSchemaTests {
    func decode(_ schema: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(schema.utf8))
        return try #require(object as? [String: Any])
    }

    func itemsSchema(_ root: [String: Any]) throws -> [String: Any] {
        let properties = try #require(root["properties"] as? [String: Any])
        return try #require(properties["items"] as? [String: Any])
    }

    func itemProperties(_ root: [String: Any], at index: Int) throws -> [String: Any] {
        let prefix = try #require(try itemsSchema(root)["prefixItems"] as? [[String: Any]])
        return try #require(prefix[index]["properties"] as? [String: Any])
    }

    func schema(
        keys: [String] = ["e1"],
        timedKeys: Set<String> = ["e1"],
        activityTypes: [String] = ["Development", "Meeting"],
        classifications: [String] = ["Billable"]
    ) throws -> [String: Any] {
        try decode(ResponseSchema.json(
            keys: keys, timedKeys: timedKeys, activityTypes: activityTypes, classifications: classifications))
    }

    @Test func schemaHasOneItemPerKeyInOrder() throws {
        let root = try schema(keys: ["e1", "e2"])
        let items = try itemsSchema(root)
        let prefix = try #require(items["prefixItems"] as? [[String: Any]])

        #expect(prefix.count == 2)
        let key = try #require(try itemProperties(root, at: 1)["key"] as? [String: Any])
        #expect(key["const"] as? String == "e2")
        #expect(items["minItems"] as? Int == 2)
        #expect(items["maxItems"] as? Int == 2)
        let extra = try #require(items["items"] as? NSNumber)
        #expect(CFGetTypeID(extra) == CFBooleanGetTypeID())
        #expect(extra.boolValue == false)
    }

    @Test func enumsComeFromSettingsLists() throws {
        let properties = try itemProperties(try schema(), at: 0)
        let activity = try #require(properties["activityType"] as? [String: Any])
        let classification = try #require(properties["classification"] as? [String: Any])

        #expect(activity["enum"] as? [String] == ["Development", "Meeting"])
        #expect(classification["enum"] as? [String] == ["Billable"])
    }

    @Test func schemaEscapesAndDedupesValues() throws {
        let values = ["Dev \"QA\"", "C:\\path", "Réunion", "Dev \"QA\""]
        let properties = try itemProperties(try schema(activityTypes: values), at: 0)
        let activity = try #require(properties["activityType"] as? [String: Any])

        #expect(activity["enum"] as? [String] == ["Dev \"QA\"", "C:\\path", "Réunion"])
    }

    @Test func emptyListFallsBackToString() throws {
        let properties = try itemProperties(try schema(activityTypes: []), at: 0)
        let activity = try #require(properties["activityType"] as? [String: String])

        #expect(activity == ["type": "string"])
    }

    @Test func itemPropertiesFollowPromptOrder() throws {
        let raw = ResponseSchema.json(
            keys: ["e1", "e2"], timedKeys: ["e1"], activityTypes: ["Development"], classifications: ["Billable"])
        let start = try #require(raw.range(of: #""prefixItems""#)).upperBound
        let end = try #require(raw.range(of: #""const":"e2""#)).lowerBound
        let firstItem = raw[start ..< end]
        let names = ["key", "minutes", "fixedStart", "fixedEnd", "description",
                     "ticket", "activityType", "classification"]
        let offsets = try names.map { name in
            try #require(firstItem.range(of: "\"\(name)\"")).lowerBound
        }

        #expect(offsets == offsets.sorted())
        #expect(Set(offsets).count == names.count)
    }

    @Test func nullableFieldsAllowNull() throws {
        let root = try schema()
        let properties = try itemProperties(root, at: 0)
        let ticket = try #require(properties["ticket"] as? [String: Any])
        let anyOf = try #require(ticket["anyOf"] as? [[String: String]])
        #expect(anyOf.contains(["type": "null"]))

        let prefix = try #require(try itemsSchema(root)["prefixItems"] as? [[String: Any]])
        let required = try #require(prefix[0]["required"] as? [String])
        #expect(required == ["key", "minutes", "fixedStart", "fixedEnd", "description",
                             "ticket", "activityType", "classification"])
    }

    @Test func untimedKeyForbidsFixedTimes() throws {
        let properties = try itemProperties(try schema(keys: ["e1", "e2"], timedKeys: ["e2"]), at: 0)

        #expect(properties["fixedStart"] as? [String: String] == ["type": "null"])
        #expect(properties["fixedEnd"] as? [String: String] == ["type": "null"])
    }

    @Test func timedKeyAllowsFixedTimes() throws {
        let properties = try itemProperties(try schema(keys: ["e1", "e2"], timedKeys: ["e2"]), at: 1)

        for field in ["fixedStart", "fixedEnd"] {
            let value = try #require(properties[field] as? [String: Any])
            let anyOf = try #require(value["anyOf"] as? [[String: String]])
            #expect(anyOf == [["type": "string"], ["type": "null"]])
        }
    }
}
