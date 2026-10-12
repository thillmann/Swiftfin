//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import PreferencesView
import SwiftUI
import Transmission

extension NavigationRoute {

    @MainActor
    static var liveGuide: NavigationRoute {
        NavigationRoute(
            id: "liveGuide"
        ) {
            EPGView()
        }
    }

    @MainActor
    static var liveTV: NavigationRoute {
        NavigationRoute(
            id: "liveTV",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            ContentGroupView(provider: LiveTVGroupProvider())
        }
    }

    static func mediaSourceInfo(source: MediaSourceInfo) -> NavigationRoute {
        NavigationRoute(
            id: "mediaSourceInfo",
            style: .sheet
        ) {
            MediaSourceInfoView(source: source)
        }
    }

    static func mediaStreamInfo(mediaStream: MediaStream) -> NavigationRoute {
        NavigationRoute(id: "mediaStreamInfo") {
            MediaStreamInfoView(mediaStream: mediaStream)
        }
    }

    @MainActor
    static func videoPlayer(
        provider: MediaPlayerItemProvider,
        queue: (any MediaPlayerQueue)? = nil
    ) -> NavigationRoute {
        let manager = MediaPlayerManager(
            provider: provider,
            queue: queue
        )

        return Self.videoPlayer(manager: manager)
    }

    @MainActor
    static func videoPlayer(manager: MediaPlayerManager) -> NavigationRoute {

        Container.shared.mediaPlayerManager.register {
            manager
        }

        Container.shared
            .mediaPlayerManagerPublisher()
            .send(manager)

        return NavigationRoute(
            id: "videoPlayer",
            style: .fullscreen
        ) {
            VideoPlayer(playerType: manager.preferredVideoPlayerType)
        }
    }
}


extension NavigationRoute {
    #if os(tvOS)
    static var seerrTrending: NavigationRoute {
        NavigationRoute(
            id: "seerr-trending",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            SeerrTrendingView()
        }
    }

    static func seerrUpcoming(mediaType: SeerrUpcomingView.MediaType = .movies) -> NavigationRoute {
        NavigationRoute(
            id: "seerr-upcoming-\(mediaType)",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            SeerrUpcomingView(mediaType: mediaType)
        }
    }

    static func browseBy(_ option: BrowseByOption) -> NavigationRoute {
        NavigationRoute(
            id: "\(option.kind.routePrefix)-\(option.seerrID)"
        ) {
            BrowseByOptionView(option: option)
        }
    }
    #endif


    static var channels: NavigationRoute {
        NavigationRoute(
            id: "channels"
        ) {
            #if os(iOS)
            ChannelLibraryView()
            #else
            ProgramsView()
            #endif
        }
    }
    static func videoPlayer(
        item: BaseItemDto,
        mediaSource: MediaSourceInfo? = nil,
        queue: (any MediaPlayerQueue)? = nil
    ) -> NavigationRoute {
        let provider = MediaPlayerItemProvider(item: item) { item in
            try await MediaPlayerItem.build(for: item, mediaSource: mediaSource)
        }
        return Self.videoPlayer(provider: provider, queue: queue)
    }
    static func videoPlayer(downloadRecord: DownloadRecord) -> NavigationRoute {
        let provider = MediaPlayerItemProvider(item: downloadRecord.item, offlineRecord: downloadRecord) { _ in
            try await MediaPlayerItem.buildOffline(record: downloadRecord)
        }
        return Self.videoPlayer(provider: provider)
    }
}
