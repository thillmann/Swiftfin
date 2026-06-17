//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension SeriesEpisodeSelector {

    struct EpisodeCard: View {

        @Router
        private var router

        let entry: LoadedEpisode
        let onEntryFocused: () -> Void

        @FocusState
        private var isFocused: Bool

        @State
        private var isContentFocused = false

        private var contentFocusPosterOffset: CGFloat {
            isContentFocused ? -18 : 0
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                PosterButton(
                    item: entry.episode,
                    type: .landscape,
                    overlayOptions: [.watched, .progress, .unwatched, .durationLeft],
                    imageSources: [entry.episode.imageSource(.primary, maxWidth: 300)],
                    usesContextMenu: false,
                    usesDelayedOverlayFocus: false
                ) {
                    router.route(
                        to: .videoPlayer(
                            item: entry.episode,
                            queue: EpisodeMediaPlayerQueue(episode: entry.episode)
                        )
                    )
                }
                .focused($isFocused)
                .focusedValue(\.focusedPoster, AnyPoster(entry.episode))
                .offset(y: contentFocusPosterOffset)
                .animation(.easeOut(duration: 0.18), value: isContentFocused)
                .onChange(of: isFocused) { _, newValue in
                    if newValue {
                        onEntryFocused()
                    }
                }

                SeriesEpisodeSelector.EpisodeContent(
                    subHeader: entry.locator,
                    header: entry.title,
                    content: entry.overview,
                    releaseDate: entry.releaseDateLabel,
                    isPosterFocused: isFocused,
                    onFocusChange: { isFocused in
                        isContentFocused = isFocused

                        if isFocused {
                            onEntryFocused()
                        }
                    }
                ) {
                    router.route(to: .item(item: entry.episode))
                }
            }
        }

        init(
            entry: LoadedEpisode,
            onEntryFocused: @escaping () -> Void = {}
        ) {
            self.entry = entry
            self.onEntryFocused = onEntryFocused
        }
    }
}
