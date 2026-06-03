//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

private let landscapeMaxWidth: CGFloat = 500
private let portraitMaxWidth: CGFloat = 500

struct PosterButton<Item: Poster>: View {

    @EnvironmentTypeValue<Item>(\.posterOverlayRegistry)
    private var posterOverlayRegistry

    @FocusState
    private var isFocused: Bool

    private let item: Item
    private let prefersBlurHashPlaceholder: Bool
    private let type: PosterDisplayType
    private let action: () -> Void

    init(
        item: Item,
        type: PosterDisplayType,
        prefersBlurHashPlaceholder: Bool = true,
        action: @escaping () -> Void
    ) {
        self.item = item
        self.prefersBlurHashPlaceholder = prefersBlurHashPlaceholder
        self.type = type
        self.action = action
    }

    var body: some View {
        let overlay = posterOverlayRegistry?(item) ??
            PosterButton.DefaultOverlay(item: item)
            .eraseToAnyView()

        Button {
            action()
        } label: {
            PosterImage(
                item: item,
                type: type,
                prefersBlurHashPlaceholder: prefersBlurHashPlaceholder
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                overlay
                    .environment(\.isPosterFocused, isFocused)
            }
            .posterStyle(type)
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .focusedValue(\.focusedPoster, AnyPoster(item))
        .accessibilityLabel(item.displayTitle)
        .matchedContextMenu(for: item)
    }
}

extension PosterButton {

    // TODO: Find better way for these indicators, see EpisodeCard
    struct DefaultOverlay: View {

        @Default(.accentColor)
        private var accentColor

        @Default(.Customization.Indicators.showUnplayed)
        private var showUnplayed
        @Default(.Customization.Indicators.showPlayed)
        private var showPlayed

        @Default(.Customization.Indicators.showFavorited)
        private var showFavorited
        @Default(.Customization.Indicators.showProgress)
        private var showProgress

        let item: Item

        var body: some View {
            ZStack {
                if let item = item as? BaseItemDto {
                    if item.canBePlayed, !item.isLiveStream, item.userData?.isPlayed == true {
                        WatchedIndicator(size: 45)
                            .isVisible(showPlayed)
                    } else {
                        if (item.userData?.playbackPositionTicks ?? 0) > 0 {
                            ProgressIndicator(progress: (item.userData?.playedPercentage ?? 0) / 100, height: 10)
                                .isVisible(showProgress)
                        } else if item.canBePlayed,
                                  !item.isLiveStream,
                                  showUnplayed == .count,
                                  (item.userData?.unplayedItemCount ?? 0) > 0
                        {
                            UnwatchedIndicator(
                                size: 45,
                                count: item.userData?.unplayedItemCount
                            )
                            .foregroundStyle(accentColor.overlayColor, accentColor)
                        }
                    }

                    if item.userData?.isFavorite == true {
                        FavoriteIndicator(size: 45)
                            .isVisible(showFavorited)
                    }
                }
            }
        }
    }
}
