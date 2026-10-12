//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import Logging

// TODO: build report of determined values for playback information
//       - transcode, video stream, path

extension MediaPlayerItem {

    /// The main `MediaPlayerItem` builder for normal online usage.
    static func build(
        for requestedItem: BaseItemDto,
        mediaSource _initialMediaSource: MediaSourceInfo? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        videoPlayerType: VideoPlayerType = Defaults[.VideoPlayer.videoPlayerType],
        requestedBitrate: PlaybackBitrate = Defaults[.VideoPlayer.Playback.appMaximumBitrate],
        compatibilityMode: PlaybackCompatibility = Defaults[.VideoPlayer.Playback.compatibilityMode],
        modifyItem: ((inout BaseItemDto) -> Void)? = nil
    ) async throws -> MediaPlayerItem {

        let logger = Logger.swiftfin()

        guard let userSession = Container.shared.currentUserSession() else {
            logger.critical("No user session!")
            throw ErrorMessage(L10n.unknownError)
        }

        let initialItem: BaseItemDto
        if requestedItem.type == .program {
            guard requestedItem.isAiring,
                  let channel = try await requestedItem.getChannel(for: requestedItem, userSession: userSession)
            else { throw ErrorMessage(L10n.unknownError) }

            initialItem = channel
        } else {
            initialItem = requestedItem
        }
        guard let itemID = initialItem.id else {
            logger.critical("No item ID!")
            throw ErrorMessage(L10n.unknownError)
        }

        let storedItem = try await userSession.getFullItem(initialItem)
        guard var item = storedItem.value else { throw ItemStore.StoreError.itemUnavailable }

        #if !os(tvOS)
        // Other platforms retain the existing version-list hydration flow.
        if let sourceItem = try? await PlaybackStreamResolver.mediaSourceItem(
            itemID: itemID,
            client: userSession.client
        ),
            let mediaSources = sourceItem.mediaSources,
            mediaSources.isNotEmpty
        {
            item.mediaSources = mediaSources
            item.mediaSourceCount = sourceItem.mediaSourceCount ?? mediaSources.count
        }
        #endif

        if let modifyItem {
            modifyItem(&item)
        }

        let initialMediaSource: MediaSourceInfo?
        #if os(tvOS)
        initialMediaSource = {
            if let _initialMediaSource {
                return _initialMediaSource
            }

            return item.mediaSources?.first
        }()
        #else
        guard let resolvedInitialMediaSource = {
            if let _initialMediaSource {
                return _initialMediaSource
            }

            return item.mediaSources?.first
        }() else {
            logger.error("No media sources for item \(itemID)!")
            throw ErrorMessage(L10n.unknownError)
        }

        initialMediaSource = resolvedInitialMediaSource
        #endif

        let requestedMediaSource = initialMediaSource.map {
            PlaybackStreamResolver.currentMediaSource(
                requested: $0,
                from: item.mediaSources,
                logger: logger
            )
        }

        let maxBitrate = try await MediaPlayerManager.getMaxBitrate(for: requestedBitrate)

        let deviceProfile = DeviceProfile.build(
            for: videoPlayerType,
            compatibilityMode: compatibilityMode,
            maxBitrate: maxBitrate
        )

        var playbackInfo = PlaybackInfoDto()
        playbackInfo.enableDirectPlay = true
        playbackInfo.enableDirectStream = true
        playbackInfo.enableTranscoding = true
        playbackInfo.allowVideoStreamCopy = true
        playbackInfo.allowAudioStreamCopy = true
        playbackInfo.isAutoOpenLiveStream = true
        playbackInfo.deviceProfile = deviceProfile
        playbackInfo.liveStreamID = requestedMediaSource?.liveStreamID
        playbackInfo.maxStreamingBitrate = maxBitrate
        playbackInfo.userID = userSession.user.id
        playbackInfo.audioStreamIndex = audioStreamIndex
        playbackInfo.subtitleStreamIndex = item.isLiveStream ? subtitleStreamIndex ?? -1 : subtitleStreamIndex

        if !item.isLiveStream, requestedMediaSource?.type != .placeholder {
            playbackInfo.mediaSourceID = requestedMediaSource?.id
        }

        let playbackInfoParameters = Paths.GetPostedPlaybackInfoParameters(
            userID: userSession.user.id,
            maxStreamingBitrate: maxBitrate,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: playbackInfo.subtitleStreamIndex,
            mediaSourceID: playbackInfo.mediaSourceID,
            liveStreamID: requestedMediaSource?.liveStreamID
        )

        let request = Paths.getPostedPlaybackInfo(
            itemID: itemID,
            parameters: playbackInfoParameters,
            playbackInfo
        )

        var playbackResponse: PlaybackInfoResponseEnvelope

        do {
            playbackResponse = try await retryPlaybackInfoAfterTimeout(
                itemID: itemID,
                logger: logger
            ) {
                try await userSession.client
                    .send(
                        request.withResponse(PlaybackInfoResponseEnvelope.self)
                    )
                    .value
            }
        } catch {
            logger.error("PlaybackInfo request failed for item \(itemID): \(error.localizedDescription)")
            throw error
        }

        var responseSources = playbackResponse.playbackInfo.mediaSources ?? []

        if responseSources.isEmpty {
            logger.warning(
                "PlaybackInfo returned no sources (error=\(String(describing: playbackResponse.playbackInfo.errorCode))); retrying without a device profile"
            )

            var profileFreePlaybackInfo = playbackInfo
            profileFreePlaybackInfo.deviceProfile = nil
            let fallbackRequest = Paths.getPostedPlaybackInfo(
                itemID: itemID,
                parameters: playbackInfoParameters,
                profileFreePlaybackInfo
            )

            do {
                let fallbackResponse = try await retryPlaybackInfoAfterTimeout(
                    itemID: itemID,
                    logger: logger
                ) {
                    try await userSession.client
                        .send(
                            fallbackRequest.withResponse(PlaybackInfoResponseEnvelope.self)
                        )
                        .value
                }
                let fallbackSources = fallbackResponse.playbackInfo.mediaSources ?? []

                if fallbackSources.isNotEmpty {
                    playbackResponse = fallbackResponse
                    responseSources = fallbackSources
                }
            } catch {
                logger.error("PlaybackInfo fallback request failed for item \(itemID): \(error.localizedDescription)")
            }
        }

        guard let mediaSource = PlaybackStreamResolver.selectedMediaSource(
            from: responseSources,
            requested: requestedMediaSource,
            logger: logger
        ) else {
            throw ErrorMessage("Unable to find media source for item")
        }
        guard storedItem.value != nil else { throw ItemStore.StoreError.itemUnavailable }

        item.runTimeTicks = mediaSource.runTimeTicks ?? item.runTimeTicks

        guard let playSessionID = playbackResponse.playbackInfo.playSessionID else {
            throw ErrorMessage("No associated play session ID")
        }

        let playbackURL = try PlaybackStreamResolver.url(
            item: item,
            mediaSource: mediaSource,
            directStreamMediaSources: playbackResponse.directStreamMediaSources,
            playSessionID: playSessionID,
            client: userSession.client
        )

        let previewImageProvider: (any PreviewImageProvider)? = {
            let previewImageScrubbingSetting = StoredValues[.User.previewImageScrubbing]
            lazy var chapterPreviewImageProvider: ChapterPreviewImageProvider? = {
                if let chapters = item.fullChapterInfo, chapters.contains(where: { $0.imageSource?.url != nil }) {
                    return ChapterPreviewImageProvider(chapters: chapters)
                }
                return nil
            }()

            if case let PreviewImageScrubbingOption.trickplay(fallbackToChapters: fallbackToChapters) = previewImageScrubbingSetting {
                if let mediaSourceID = mediaSource.id,
                   let trickplayInfo = item.trickplay?[mediaSourceID]?.first
                {
                    return TrickplayPreviewImageProvider(
                        info: trickplayInfo.value,
                        itemID: itemID,
                        mediaSourceID: mediaSourceID,
                        runtime: item.runtime ?? .zero
                    )
                }

                if fallbackToChapters {
                    return chapterPreviewImageProvider
                }
            } else if previewImageScrubbingSetting == .chapters {
                return chapterPreviewImageProvider
            }

            return nil
        }()

        return .init(
            baseItem: item,
            mediaSource: mediaSource,
            playSessionID: playSessionID,
            url: playbackURL,
            requestedBitrate: requestedBitrate,
            deviceProfile: deviceProfile,
            initialAudioStreamIndex: audioStreamIndex,
            initialSubtitleStreamIndex: subtitleStreamIndex,
            previewImageProvider: previewImageProvider,
            thumbnailProvider: { await storedItem.value?.getNowPlayingImage() }
        )
    }
}

private func retryPlaybackInfoAfterTimeout<Value>(
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

private enum PlaybackStreamResolver {

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

    static func url(
        item: BaseItemDto,
        mediaSource: MediaSourceInfo,
        directStreamMediaSources: [PlaybackInfoResponseEnvelope.DirectStreamMediaSource],
        playSessionID: String,
        client: JellyfinClient
    ) throws -> URL {

        guard let itemID = item.id else {
            throw ErrorMessage("No item ID while building online media player item!")
        }

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

        if let remoteURL = remoteDirectPlayURL(item: item, mediaSource: mediaSource) {
            return remoteURL
        }

        if item.mediaType == .video {

            let mediaSourceID = mediaSource.id ?? itemID
            let videoStreamParameters = Paths.GetVideoStreamParameters(
                isStatic: true,
                tag: mediaSource.eTag ?? item.etag,
                playSessionID: playSessionID,
                mediaSourceID: mediaSourceID,
                liveStreamID: mediaSource.liveStreamID
            )

            let videoStreamRequest = Paths.getVideoStream(
                itemID: itemID,
                parameters: videoStreamParameters
            )

            guard let videoStreamURL = client.url(with: videoStreamRequest, queryAPIKey: true)
            else { throw ErrorMessage("Unable to make video stream URL") }

            return videoStreamURL
        }

        guard let path = mediaSource.path, let streamURL = URL(
            string: path
        ) else { throw ErrorMessage("Unable to make stream URL") }

        return streamURL
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
