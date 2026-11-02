//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import Logging

func retryPlaybackInfoAfterTimeout<Value>(
    itemID: String,
    logger: Logger,
    operation: () async throws -> Value
) async throws -> Value {

    do {
        return try await operation()
    } catch {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain,
              nsError.code == URLError.timedOut.rawValue
        else {
            throw error
        }

        logger.warning("PlaybackInfo request timed out for item \(itemID); retrying once")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return try await operation()
    }
}

enum PlaybackStreamResolver {

    static func mediaSourceItem(
        itemID: String,
        client: JellyfinClient
    ) async throws -> BaseItemDto? {

        var parameters = Paths.GetItemsParameters()
        parameters.fields = .MediaSourceFields
        parameters.ids = [itemID]
        parameters.limit = 1

        let response = try await client.send(Paths.getItems(parameters: parameters))
        return response.value.items?.first
    }

    /// Refresh caller-provided source metadata without changing the selected
    /// version. Some servers use the parent item ID for every source, so the
    /// source ETag is the only unique selection key.
    static func currentMediaSource(
        requested: MediaSourceInfo,
        from currentMediaSources: [MediaSourceInfo]?,
        logger: Logger
    ) -> MediaSourceInfo {

        guard let currentMediaSources, currentMediaSources.isNotEmpty else {
            return requested
        }

        if let requestedETag = requested.eTag,
           let currentSource = currentMediaSources.first(where: { $0.eTag == requestedETag })
        {
            return currentSource
        }

        if let requestedID = requested.id,
           let currentSource = currentMediaSources.first(where: { $0.id == requestedID })
        {
            return currentSource
        }

        logger.warning(
            "Requested media source id=\(requested.id ?? "nil") is not present in the refreshed item; preserving the explicit selection"
        )
        return requested
    }

    static func selectedMediaSource(
        from mediaSources: [MediaSourceInfo]?,
        requested requestedMediaSource: MediaSourceInfo?,
        logger: Logger
    ) -> MediaSourceInfo? {

        guard let mediaSources, mediaSources.isNotEmpty else { return nil }

        if let requestedETag = requestedMediaSource?.eTag,
           let source = mediaSources.first(where: { $0.eTag == requestedETag })
        {
            return source
        }

        if let requestedID = requestedMediaSource?.id,
           let source = mediaSources.first(where: { $0.id == requestedID })
        {
            return source
        }

        if let directPlaySource = mediaSources.first(where: { $0.isSupportsDirectPlay == true }) {
            return directPlaySource
        }

        if let directStreamSource = mediaSources.first(where: { $0.isSupportsDirectStream == true }) {
            return directStreamSource
        }

        if let transcodeSource = mediaSources.first(where: { $0.isSupportsTranscoding == true }) {
            return transcodeSource
        }

        logger.warning("No playable media source in PlaybackInfo response; using the first returned source")
        return mediaSources.first
    }

    /// Server-provided delivery URLs that take precedence over a static stream URL.
    /// Returns `nil` when the caller should build the static item stream URL.
    static func preferredURL(
        item: BaseItemDto,
        mediaSource: MediaSourceInfo,
        directStreamMediaSources: [PlaybackInfoResponseEnvelope.DirectStreamMediaSource],
        client: JellyfinClient
    ) throws -> URL? {

        if let resolvedDirectStreamURL = directStreamURL(
            from: directStreamMediaSources,
            mediaSource: mediaSource,
            client: client
        ) {
            return resolvedDirectStreamURL
        }

        if let deliveryPath = mediaSource.transcodingURL, !deliveryPath.isEmpty {
            guard let url = authenticatedServerURL(path: deliveryPath, client: client) else {
                throw ErrorMessage("Unable to make server playback URL")
            }

            return url
        }

        return remoteDirectPlayURL(item: item, mediaSource: mediaSource)
    }

    static func remoteDirectPlayURL(item: BaseItemDto, mediaSource: MediaSourceInfo) -> URL? {
        guard !item.isLiveStream,
              mediaSource.isRemote == true,
              mediaSource.isSupportsDirectPlay == true,
              mediaSource.requiredHTTPHeaders?.isEmpty != false
        else { return nil }

        return remoteHTTPURL(from: mediaSource.path)
    }

    private static func remoteHTTPURL(from path: String?) -> URL? {
        guard let path,
              let url = URL(string: path),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else { return nil }

        return url
    }

    private static func directStreamURL(
        from directStreamMediaSources: [PlaybackInfoResponseEnvelope.DirectStreamMediaSource],
        mediaSource: MediaSourceInfo,
        client: JellyfinClient
    ) -> URL? {

        guard mediaSource.isSupportsDirectStream == true,
              mediaSource.requiredHTTPHeaders?.isEmpty != false,
              let mediaSourceID = mediaSource.id,
              let directStreamMediaSource = directStreamMediaSources.first(where: {
                  $0.id == mediaSourceID
                      && ($0.playMethod == nil || $0.playMethod == PlayMethod.directStream.rawValue)
              }),
              let directStreamPath = directStreamMediaSource.directStreamURL,
              !directStreamPath.isEmpty
        else { return nil }

        if let url = URL(string: directStreamPath), url.scheme != nil {
            guard let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil
            else { return nil }

            return authenticatedURLIfCurrentServer(url, client: client)
        }

        guard !directStreamPath.hasPrefix("//") else { return nil }

        return authenticatedServerURL(path: directStreamPath, client: client)
    }

    private static func authenticatedServerURL(path: String, client: JellyfinClient) -> URL? {
        guard let url = client.url(path: path) else { return nil }

        return appendingAPIKey(to: url, accessToken: client.accessToken)
    }

    private static func authenticatedURLIfCurrentServer(_ url: URL, client: JellyfinClient) -> URL {
        guard url.scheme?.lowercased() == client.configuration.url.scheme?.lowercased(),
              url.host?.lowercased() == client.configuration.url.host?.lowercased(),
              url.port == client.configuration.url.port
        else { return url }

        return appendingAPIKey(to: url, accessToken: client.accessToken)
    }

    private static func appendingAPIKey(to url: URL, accessToken: String?) -> URL {
        guard let accessToken,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.contains(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame }) != true
        else { return url }

        var queryItems = components.queryItems ?? []
        queryItems.append(.init(name: "api_key", value: accessToken))
        components.queryItems = queryItems
        return components.url ?? url
    }
}

/// Raw playback response metadata shared with exact-source download
/// resolution. JellyfinAPI does not currently expose `DirectStreamUrl` on its
/// generated `MediaSourceInfo` model.
struct PlaybackInfoResponseEnvelope: Decodable {

    let playbackInfo: PlaybackInfoResponse
    let directStreamMediaSources: [DirectStreamMediaSource]

    init(from decoder: Decoder) throws {
        playbackInfo = try PlaybackInfoResponse(from: decoder)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        directStreamMediaSources = try container.decodeIfPresent(
            [DirectStreamMediaSource].self,
            forKey: .mediaSources
        ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
    }

    struct DirectStreamMediaSource: Decodable {

        let id: String?
        let directStreamURL: String?
        let playMethod: String?

        private enum CodingKeys: String, CodingKey {
            case id = "Id"
            case directStreamURL = "DirectStreamUrl"
            case playMethod = "PlayMethod"
        }
    }
}
