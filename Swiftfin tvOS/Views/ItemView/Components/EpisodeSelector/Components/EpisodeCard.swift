//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftUI

extension SeriesEpisodeSelector {

    struct EpisodeCard: View {

        @Router
        private var router

        let episode: BaseItemDto

        @FocusState
        private var isFocused: Bool

        private var episodeContent: String {
            if episode.isUnaired {
                episode.airDateLabel ?? L10n.noOverviewAvailable
            } else {
                episode.overview ?? L10n.noOverviewAvailable
            }
        }

        private var releaseDateLabel: String? {
            guard let premiereDate = episode.premiereDate else {
                return nil
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM yyyy"
            return formatter.string(from: premiereDate)
        }

        var body: some View {
            VStack(alignment: .leading) {
                Button {
                    router.route(
                        to: .videoPlayer(
                            item: episode,
                            queue: EpisodeMediaPlayerQueue(episode: episode)
                        )
                    )
                } label: {
                    ZStack {
                        Color.clear

                        ImageView(episode.imageSource(.primary, maxWidth: 500))
                            .failure {
                                SystemImageContentView(systemName: episode.systemImage)
                            }
                    }
                    .posterStyle(.landscape)
                    .overlay {
                        PosterButton<BaseItemDto>.DefaultOverlay(item: episode)
                            .environment(\.isPosterFocused, isFocused)
                            .posterOverlayComponents([.playIcon, .progressBar, .durationLeft])
                    }
                }
                .buttonStyle(.card)
                .posterShadow()
                .focused($isFocused)
                .focusedValue(\.focusedPoster, AnyPoster(episode))
                .matchedContextMenu(for: episode)

                SeriesEpisodeSelector.EpisodeContent(
                    subHeader: episode.episodeLocator ?? .emptyDash,
                    header: episode.displayTitle,
                    content: episodeContent,
                    releaseDate: releaseDateLabel,
                    isPosterFocused: isFocused
                ) {
                    router.route(to: .item(item: episode))
                }
            }
        }
    }
}
