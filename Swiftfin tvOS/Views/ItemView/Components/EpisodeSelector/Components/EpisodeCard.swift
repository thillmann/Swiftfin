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
        let isEntryFocused: Bool
        let onPosterFocusChange: (Bool) -> Void

        @FocusState
        private var isFocused: Bool

        @State
        private var isContentFocused = false

        private var contentFocusPosterOffset: CGFloat {
            isContentFocused ? -18 : 0
        }

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
            VStack(alignment: .leading, spacing: 6) {
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
                            .posterOverlayFocus(isFocused)
                            .posterOverlayComponents([.playIcon, .progressBar, .durationLeft])
                    }
                }
                .buttonStyle(.card)
                .posterShadow()
                .focused($isFocused)
                .focusedValue(\.focusedPoster, AnyPoster(episode))
                .matchedContextMenu(for: episode)
                .offset(y: contentFocusPosterOffset)
                .animation(.easeOut(duration: 0.18), value: isContentFocused)
                .onChange(of: isFocused) { _, newValue in
                    onPosterFocusChange(newValue)
                }
                .onChange(of: isEntryFocused) { _, newValue in
                    if newValue {
                        isFocused = true
                    }
                }
                .onAppear {
                    if isEntryFocused {
                        isFocused = true
                    }
                }

                SeriesEpisodeSelector.EpisodeContent(
                    subHeader: episode.episodeLocator ?? .emptyDash,
                    header: episode.displayTitle,
                    content: episodeContent,
                    releaseDate: releaseDateLabel,
                    isPosterFocused: isFocused,
                    onFocusChange: { isContentFocused = $0 }
                ) {
                    router.route(to: .item(item: episode))
                }
            }
        }

        init(
            episode: BaseItemDto,
            isEntryFocused: Bool = false,
            onPosterFocusChange: @escaping (Bool) -> Void = { _ in }
        ) {
            self.episode = episode
            self.isEntryFocused = isEntryFocused
            self.onPosterFocusChange = onPosterFocusChange
        }
    }
}
