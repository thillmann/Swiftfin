//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI

enum DownloadTransferStrategy: String, Codable, Hashable {
    case directHTTPSource
    case itemDownload
    case staticHTTPStream
}

enum DownloadSourceKind: Equatable {
    case disc
    case file
    case finiteHTTP
    case hls
    case live
    case unsupported
}

/// Pure source classification shared by resolution and UI eligibility.
enum DownloadSourceClassifier {

    static func kind(itemIsLive: Bool, source: MediaSourceInfo) -> DownloadSourceKind {
        if itemIsLive || source.isInfiniteStream == true || source.liveStreamID?.isEmpty == false {
            return .live
        }
        if source.videoType == .bluRay || source.videoType == .dvd {
            return .disc
        }
        if isHLS(source) {
            return .hls
        }
        // Some remote/plugin providers return an absolute HTTP(S) URL while
        // labelling the refreshed source as File (or omitting Protocol). The
        // URL is the authoritative transport signal in that case. Keep this
        // after the live, disc, and HLS checks so those remain unsupported.
        if directHTTPURL(for: source) != nil || source.protocol == .http {
            return .finiteHTTP
        }
        if source.protocol == .file || source.protocol == nil {
            return .file
        }
        return .unsupported
    }

    static func inferredStrategy(itemIsLive: Bool, source: MediaSourceInfo) -> DownloadTransferStrategy? {
        switch kind(itemIsLive: itemIsLive, source: source) {
        case .file:
            .itemDownload
        case .finiteHTTP:
            directHTTPURL(for: source) == nil ? .staticHTTPStream : .directHTTPSource
        case .disc, .hls, .live, .unsupported:
            nil
        }
    }

    /// Returns only finite, absolute HTTP(S) provider URLs. This intentionally
    /// excludes playlist URLs even if a server labels them as HTTP media.
    static func directHTTPURL(for source: MediaSourceInfo) -> URL? {
        finiteHTTPURL(from: source.path)
    }

    static func finiteHTTPURL(from value: String?) -> URL? {
        guard let value,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false,
              !["m3u", "m3u8"].contains(url.pathExtension.lowercased())
        else { return nil }
        return url
    }

    static func routeContainer(for source: MediaSourceInfo) -> String? {
        normalizedExtension(source.container?.split(separator: ",").first.map(String.init))
    }

    static func exactSelection(
        _ selected: MediaSourceInfo,
        in availableSources: [MediaSourceInfo]
    ) -> MediaSourceInfo? {
        if let eTag = selected.eTag, !eTag.isEmpty {
            let matches = availableSources.filter { $0.eTag == eTag }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { return nil }
        }
        if let id = selected.id, !id.isEmpty {
            let matches = availableSources.filter { $0.id == id }
            if matches.count == 1 { return matches[0] }
            let exactMatches = matches.filter { $0 == selected }
            return exactMatches.count == 1 ? exactMatches[0] : nil
        }
        let exactMatches = availableSources.filter { $0 == selected }
        return exactMatches.count == 1 ? exactMatches[0] : nil
    }

    static func outputExtension(
        suggestedFilename: String?,
        mimeType: String?,
        source: MediaSourceInfo
    ) -> String {
        let candidates = [
            routeContainer(for: source),
            suggestedFilename.flatMap { normalizedExtension(URL(fileURLWithPath: $0).pathExtension) },
            source.path.flatMap { normalizedExtension(URL(string: $0)?.pathExtension) },
            extensionForMIMEType(mimeType),
        ]
        return candidates.compactMap(\.self).first ?? "media"
    }

    private static func isHLS(_ source: MediaSourceInfo) -> Bool {
        if source.transcodingSubProtocol == .hls { return true }
        let container = source.container?.lowercased() ?? ""
        if container.contains("m3u8") || container.contains("hls") { return true }
        let pathExtension = source.path.flatMap { URL(string: $0)?.pathExtension.lowercased() }
        return pathExtension == "m3u8" || pathExtension == "m3u"
    }

    private static func normalizedExtension(_ value: String?) -> String? {
        guard let value = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !value.isEmpty,
            value.count <= 12,
            value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }),
            !["strm", "m3u", "m3u8", "hls"].contains(value)
        else { return nil }

        switch value {
        case "matroska": return "mkv"
        case "mpegts": return "ts"
        default: return value
        }
    }

    private static func extensionForMIMEType(_ mimeType: String?) -> String? {
        guard let mimeType = mimeType?.lowercased() else { return nil }
        if mimeType.contains("matroska") { return "mkv" }
        if mimeType.contains("mp4") { return "mp4" }
        if mimeType.contains("quicktime") { return "mov" }
        if mimeType.contains("webm") { return "webm" }
        if mimeType.contains("mpeg") { return "mpeg" }
        return nil
    }
}

/// Durable metadata for the selected version of one downloaded item.
/// The manager enforces one surviving record per server, user, and
/// presentation item while retaining media-source identity in this record.
struct DownloadRecord: Codable, Hashable, Identifiable {

    enum Status: String, Codable, Hashable {
        case resolving
        case queued
        case downloading
        case paused
        case finalizing
        case completed
        case failed
        case cancelled
        case deleting
    }

    struct OfflineProgress: Codable, Hashable {
        var positionTicks: Int
        var isPlayed: Bool
        var updatedAt: Date
    }

    /// Stable, version-aware transfer identity. A replacement may use a new
    /// ID when the selected media source changes.
    let id: String
    let serverID: String
    let userID: String
    let presentationItemID: String
    let mediaSourceID: String

    var resolvedDownloadItemID: String?
    /// Optional for backwards-compatible decoding of records created before
    /// transfer strategies were persisted. The manager infers and saves it.
    var transferStrategy: DownloadTransferStrategy?
    var item: BaseItemDto
    var mediaSource: MediaSourceInfo
    /// Ordered sources remaining for an automatically selected download.
    /// Explicit user selections leave this nil and never switch versions.
    var remainingMediaSources: [MediaSourceInfo]?
    /// Identifies the user enqueue operation that created this record. Optional
    /// so indexes written before grouped progress continue to decode.
    var batchID: String?

    var status: Status
    var progress: Double
    var bytesWritten: Int64
    var expectedBytes: Int64?
    var transferTaskIdentifier: Int?
    var mediaFilename: String?
    var primaryImageFilename: String?
    /// Series portrait artwork used to group downloaded episodes in the
    /// offline library. Optional for records created before grouped posters.
    var seriesPrimaryImageFilename: String?
    var backdropImageFilename: String?
    /// ImageType raw values mapped to package-local filenames. Optional so
    /// manifests written before multi-artwork downloads continue to decode.
    var imageFilenames: [String: String]?
    var subtitleFilenames: [Int: String]
    var errorDescription: String?
    var offlineProgress: OfflineProgress?
    var createdAt: Date
    var updatedAt: Date

    init(
        serverID: String,
        userID: String,
        presentationItemID: String,
        mediaSourceID: String,
        item: BaseItemDto,
        mediaSource: MediaSourceInfo,
        status: Status = .resolving
    ) {
        self.id = Self.makeID(
            serverID: serverID,
            userID: userID,
            itemID: presentationItemID,
            mediaSourceID: mediaSourceID
        )
        self.serverID = serverID
        self.userID = userID
        self.presentationItemID = presentationItemID
        self.mediaSourceID = mediaSourceID
        self.transferStrategy = DownloadSourceClassifier.inferredStrategy(
            itemIsLive: item.isLiveStream,
            source: mediaSource
        )
        self.item = item
        self.mediaSource = mediaSource
        self.status = status
        self.progress = 0
        self.bytesWritten = 0
        self.expectedBytes = MediaSourceSelection.estimatedSize(for: mediaSource)
        self.subtitleFilenames = [:]
        self.createdAt = .now
        self.updatedAt = .now
    }

    static func makeID(serverID: String, userID: String, itemID: String, mediaSourceID: String) -> String {
        [serverID, userID, itemID, mediaSourceID]
            .map { Data($0.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_") }
            .joined(separator: ".")
    }
}

enum DownloadStorage {

    static var rootURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport.appendingPathComponent("Downloads", isDirectory: true)
    }

    static var indexURL: URL {
        rootURL.appendingPathComponent("Downloads.json", isDirectory: false)
    }

    static func folderURL(for record: DownloadRecord) -> URL {
        rootURL
            .appendingPathComponent(safeComponent(record.serverID), isDirectory: true)
            .appendingPathComponent(safeComponent(record.userID), isDirectory: true)
            .appendingPathComponent(safeComponent(record.presentationItemID), isDirectory: true)
            .appendingPathComponent(safeComponent(record.mediaSourceID), isDirectory: true)
    }

    static func mediaURL(for record: DownloadRecord) -> URL? {
        guard let mediaFilename = record.mediaFilename else { return nil }
        return folderURL(for: record).appendingPathComponent(mediaFilename, isDirectory: false)
    }

    static func imageURL(for record: DownloadRecord, type: ImageType) -> URL? {
        let filename = record.imageFilenames?[type.rawValue] ?? {
            switch type {
            case .primary: record.primaryImageFilename
            case .backdrop: record.backdropImageFilename
            default: nil
            }
        }()
        guard let filename else { return nil }
        return folderURL(for: record)
            .appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    static func imageURL(for record: DownloadRecord, name: String) -> URL? {
        guard let type = ImageType(rawValue: name) else { return nil }
        return imageURL(for: record, type: type)
    }

    static func seriesPrimaryImageURL(for record: DownloadRecord) -> URL? {
        guard let filename = record.seriesPrimaryImageFilename else { return nil }
        return folderURL(for: record)
            .appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    static func subtitleURL(for record: DownloadRecord, index: Int) -> URL? {
        guard let filename = record.subtitleFilenames[index] else { return nil }
        return folderURL(for: record)
            .appendingPathComponent("Subtitles", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    static func manifestURL(for record: DownloadRecord) -> URL {
        folderURL(for: record).appendingPathComponent("manifest.json", isDirectory: false)
    }

    static func metadataURL(for record: DownloadRecord) -> URL {
        folderURL(for: record)
            .appendingPathComponent("Metadata", isDirectory: true)
            .appendingPathComponent("Item.json", isDirectory: false)
    }

    static func createFolder(for record: DownloadRecord) throws {
        let folder = folderURL(for: record)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableFolder = folder
        try? mutableFolder.setResourceValues(values)
    }

    private static func safeComponent(_ value: String) -> String {
        let permitted = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let encoded = value.unicodeScalars.map { permitted.contains($0) ? String($0) : "_" }.joined()
        return encoded.isEmpty ? "unknown" : encoded
    }
}

extension DownloadRecord {
    /// AVPlayer cannot render these local containers or subtitle sidecars.
    var preferredVideoPlayerType: VideoPlayerType {
        let preferred = Defaults[.VideoPlayer.videoPlayerType]
        guard preferred == .avPlayer else { return preferred }
        let container = mediaSource.container?.lowercased() ?? ""
        return subtitleFilenames.isNotEmpty || !["mp4", "mov", "m4v"].contains(container) ? .vlc : .avPlayer
    }
}
