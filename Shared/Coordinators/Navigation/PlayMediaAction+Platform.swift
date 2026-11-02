//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

extension PlaybackIntent {

    init(item: BaseItemDto, mediaSource: MediaSourceInfo?, queue: (any MediaPlayerQueue)? = nil) {
        var configuration = MediaPlaybackConfiguration()

        if let mediaSource {
            configuration.selectMediaSource(id: mediaSource.id)
        }

        self.init(item: item, configuration: configuration, queue: queue)
    }

    /// Plays the download from local storage, without a server round trip.
    init(downloadRecord: DownloadRecord) {
        var configuration = MediaPlaybackConfiguration()
        configuration.selectMediaSource(id: downloadRecord.mediaSource.id)
        configuration.offlineRecordID = downloadRecord.id

        self.init(item: downloadRecord.item, configuration: configuration)
    }
}

extension PlayMediaAction {

    func callAsFunction(item: BaseItemDto, mediaSource: MediaSourceInfo? = nil, queue: (any MediaPlayerQueue)? = nil) {
        callAsFunction(intent: PlaybackIntent(item: item, mediaSource: mediaSource, queue: queue))
    }

    func callAsFunction(downloadRecord: DownloadRecord) {
        callAsFunction(intent: PlaybackIntent(downloadRecord: downloadRecord))
    }
}
