//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Decodes existing offline snapshots after the SDK made UserData.Key required.
/// Only absent/null keys are supplied; all saved progress and metadata remain.
enum OfflineMetadataDecoder {
    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let isMissingUserDataKey: Bool = switch error {
            case let DecodingError.keyNotFound(key, context):
                key.stringValue == "Key" && context.codingPath.last?.stringValue == "UserData"

            case let DecodingError.valueNotFound(_, context):
                context.codingPath.last?.stringValue == "Key"
                    && context.codingPath.dropLast().last?.stringValue == "UserData"

            default:
                false
            }
            guard isMissingUserDataKey else { throw error }

            let object = try JSONSerialization.jsonObject(with: data)
            let migrated: Any
            if let records = object as? [[String: Any]] {
                migrated = records.map(migrateRecord)
            } else if let value = object as? [String: Any] {
                migrated = value["item"] != nil ? migrateRecord(value) : migrateItem(value, fallbackID: nil)
            } else {
                throw error
            }
            return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: migrated))
        }
    }

    private static func migrateRecord(_ record: [String: Any]) -> [String: Any] {
        guard let item = record["item"] as? [String: Any] else { return record }

        var result = record
        result["item"] = migrateItem(item, fallbackID: record["presentationItemID"] as? String)
        return result
    }

    private static func migrateItem(_ item: [String: Any], fallbackID: String?) -> [String: Any] {
        guard var userData = item["UserData"] as? [String: Any],
              userData["Key"] == nil || userData["Key"] is NSNull else { return item }

        userData["Key"] = (userData["ItemId"] as? String) ?? (item["Id"] as? String) ?? fallbackID ?? ""
        var result = item
        result["UserData"] = userData
        return result
    }
}
