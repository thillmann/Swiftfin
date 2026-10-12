//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum TopShelfResumeCache {

    static let appGroupIdentifier = Bundle.main.object(
        forInfoDictionaryKey: "SwiftfinAppGroupIdentifier"
    ) as? String ?? "group.org.jellyfin.swiftfin"

    private static let fileName = "top-shelf-resume-items.json"

    struct Entry: Codable, Hashable, Identifiable {
        let id: String
        let title: String
        let contextTitle: String?
        let summary: String?
        let genre: String?
        let duration: TimeInterval?
        let creationDate: Date?
        let imageURL: URL?
        let displayURL: URL?
        let playURL: URL?
    }

    static func readEntries() -> [Entry] {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([Entry].self, from: data)
        } catch {
            return []
        }
    }

    static func write(entries: [Entry]) {
        guard let fileURL else { return }

        do {
            let data = try JSONEncoder().encode(entries)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Top Shelf should never block the home screen or app refresh.
        }
    }

    static func artworkURL(for identifier: String) -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }

        let safeIdentifier = identifier.replacingOccurrences(
            of: "[^a-zA-Z0-9._-]",
            with: "-",
            options: .regularExpression
        )

        return containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("TopShelfArtwork", isDirectory: true)
            .appendingPathComponent("\(safeIdentifier)-v6.jpg", isDirectory: false)
    }

    private static var fileURL: URL? {
        let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )

        return containerURL?
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
