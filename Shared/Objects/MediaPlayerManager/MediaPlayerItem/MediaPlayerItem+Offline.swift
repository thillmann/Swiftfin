//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import UIKit

extension MediaPlayerItem {

    var isOffline: Bool {
        configuration.offlineRecordID != nil
    }

    /// Builds playback entirely from durable local metadata and file URLs.
    /// No PlaybackInfo or streaming request is made.
    static func buildOffline(
        recordID: String,
        intent: PlaybackIntent,
        profile: PlaybackProfile
    ) throws -> MediaPlayerItem {
        guard let record = Container.shared.downloadManager().record(id: recordID),
              record.status == .completed,
              let mediaURL = DownloadStorage.mediaURL(for: record),
              FileManager.default.fileExists(atPath: mediaURL.path)
        else { throw ErrorMessage("The downloaded media file is unavailable.") }

        var item = record.item
        if let progress = record.offlineProgress {
            item.userData?.playbackPositionTicks = progress.positionTicks
            item.userData?.isPlayed = progress.isPlayed
        }

        var mediaSource = record.mediaSource
        mediaSource.transcodingURL = nil
        mediaSource.protocol = .file
        mediaSource.isRemote = false

        if var streams = mediaSource.mediaStreams {
            for index in streams.indices {
                guard let streamIndex = streams[index].index,
                      let subtitleURL = DownloadStorage.subtitleURL(for: record, index: streamIndex)
                else { continue }

                streams[index].deliveryURL = subtitleURL.absoluteString
                streams[index].deliveryMethod = .external
                streams[index].isExternal = true
            }
            mediaSource.mediaStreams = streams
        }

        var configuration = intent.configuration
        configuration.prepare(for: item, source: mediaSource, profile: profile)
        configuration.finish(source: mediaSource, initialSource: mediaSource)

        let deviceProfile: DeviceProfile = {
            guard case let .local(playerType) = profile else { return DeviceProfile() }

            var directPlay = configuration
            directPlay.compatibilityMode = .directPlay
            return .build(for: playerType, configuration: directPlay, mediaSource: mediaSource)
        }()

        let thumbnailProvider: ThumbnailProvider? = {
            let imageURL = DownloadStorage.imageURL(for: record, name: "Backdrop")
                ?? DownloadStorage.imageURL(for: record, name: "Primary")
            guard let imageURL else { return nil }

            return { UIImage(contentsOfFile: imageURL.path) }
        }()

        return .init(
            baseItem: item,
            mediaSource: mediaSource,
            playSessionID: "offline-\(record.id)",
            url: mediaURL,
            configuration: configuration,
            deviceProfile: deviceProfile,
            chapters: [],
            temporaryFiles: PlaybackTemporaryFiles(accessToken: nil),
            previewImageProvider: nil,
            thumbnailProvider: thumbnailProvider
        )
    }
}
