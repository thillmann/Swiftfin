//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct MyPosterButton<Item: Poster, Overlay: View, Fallback: View>: View {
    let item: Item
    let posterType: PosterDisplayType
    let overlayOptions: MyPosterButtonOverlayOptions
    let unplayedIndicatorType: UnplayedIndicatorType

    private let action: () -> Void
    private let fallback: () -> Fallback
    private let overlay: () -> Overlay

    init(
        item: Item,
        type: PosterDisplayType,
        overlayOptions: MyPosterButtonOverlayOptions = .default,
        unplayedIndicatorType: UnplayedIndicatorType = .none,
        action: @escaping () -> Void,
        @ViewBuilder fallback: @escaping () -> Fallback,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.item = item
        self.posterType = type
        self.overlayOptions = overlayOptions
        self.unplayedIndicatorType = unplayedIndicatorType
        self.action = action
        self.fallback = fallback
        self.overlay = overlay
    }

    var body: some View {
        Button {
            action()
        } label: {
            PosterButtonContent(
                item: item,
                posterType: posterType,
                overlayOptions: overlayOptions,
                unplayedIndicatorType: unplayedIndicatorType,
                fallback: fallback,
                overlay: overlay
            )
        }
        .buttonStyle(.card)
        .accessibilityLabel(item.displayTitle)
        .matchedContextMenu(for: item)
    }
}

extension MyPosterButton where Fallback == PosterFallbackContentView {

    init(
        item: Item,
        type: PosterDisplayType,
        overlayOptions: MyPosterButtonOverlayOptions = .default,
        unplayedIndicatorType: UnplayedIndicatorType = .none,
        action: @escaping () -> Void,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.init(
            item: item,
            type: type,
            overlayOptions: overlayOptions,
            unplayedIndicatorType: unplayedIndicatorType,
            action: action
        ) {
            PosterFallbackContentView(
                title: item.showTitle ? item.displayTitle : nil,
                systemName: item.systemImage
            )
        } overlay: {
            overlay()
        }
    }
}

extension MyPosterButton where Overlay == MyPosterButtonDefaultOverlay<Item> {

    init(
        item: Item,
        type: PosterDisplayType,
        overlayOptions: MyPosterButtonOverlayOptions = .default,
        unplayedIndicatorType: UnplayedIndicatorType = .none,
        action: @escaping () -> Void,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.init(
            item: item,
            type: type,
            overlayOptions: overlayOptions,
            unplayedIndicatorType: unplayedIndicatorType,
            action: action,
            fallback: fallback
        ) {
            MyPosterButtonDefaultOverlay(
                item: item,
                overlayOptions: overlayOptions,
                unplayedIndicatorType: unplayedIndicatorType
            )
        }
    }
}

extension MyPosterButton where Overlay == MyPosterButtonDefaultOverlay<Item>, Fallback == PosterFallbackContentView {

    init(
        item: Item,
        type: PosterDisplayType,
        overlayOptions: MyPosterButtonOverlayOptions = .default,
        unplayedIndicatorType: UnplayedIndicatorType = .none,
        action: @escaping () -> Void
    ) {
        self.init(
            item: item,
            type: type,
            overlayOptions: overlayOptions,
            unplayedIndicatorType: unplayedIndicatorType,
            action: action
        ) {
            PosterFallbackContentView(
                title: item.showTitle ? item.displayTitle : nil,
                systemName: item.systemImage
            )
        } overlay: {
            MyPosterButtonDefaultOverlay(
                item: item,
                overlayOptions: overlayOptions,
                unplayedIndicatorType: unplayedIndicatorType
            )
        }
    }
}

struct MyPosterButtonOverlayOptions: OptionSet {
    let rawValue: Int

    static let watched = Self(rawValue: 1 << 0)
    static let favorite = Self(rawValue: 1 << 1)
    static let progress = Self(rawValue: 1 << 2)
    static let unwatched = Self(rawValue: 1 << 3)

    static let `default`: Self = [
        .watched,
        .unwatched,
        .favorite,
        .progress,
    ]
}

struct PosterButtonContent<Item: Poster, Overlay: View, Fallback: View>: View {
    @Environment(\.isFocused)
    private var isFocused

    let item: Item
    let posterType: PosterDisplayType
    let overlayOptions: MyPosterButtonOverlayOptions
    let unplayedIndicatorType: UnplayedIndicatorType
    let fallback: () -> Fallback
    let overlay: () -> Overlay

    var body: some View {
        ZStack {
            PosterImage(
                item: item,
                type: posterType
            ) {
                fallback()
            }

            overlay().posterOverlayFocus(isFocused)
        }
    }
}

struct MyPosterButtonDefaultOverlay<Item: Poster>: View {
    @Environment(\.isFocused)
    private var isFocused

    let item: Item
    let overlayOptions: MyPosterButtonOverlayOptions
    let unplayedIndicatorType: UnplayedIndicatorType

    private var baseItem: BaseItemDto? {
        item as? BaseItemDto
    }

    private var isPlayed: Bool {
        baseItem?.userData?.isPlayed == true ||
            (baseItem?.userData?.playedPercentage ?? 0) >= 100
    }

    private var playbackProgress: Double {
        baseItem?.userData?.playedPercentage ?? 0.0
    }

    private var hasPlaybackProgress: Bool {
        (baseItem?.userData?.playbackPositionTicks ?? 0) > 0
    }

    private var seasonEpisodeLabel: String? {
        guard let baseItem else {
            return nil
        }

        if let seasonNumber = baseItem.parentIndexNumber,
           let episodeNumber = baseItem.indexNumber
        {
            return "S\(seasonNumber), E\(episodeNumber)"
        }

        return baseItem.seasonEpisodeLabel
    }

    private var durationLeftLabel: String? {
        if hasPlaybackProgress, !isPlayed, let progressLabel = baseItem?.progressLabel {
            return progressLabel
        }

        return baseItem?.runTimeLabel
    }

    private var canShowStatusIndicator: Bool {
        baseItem?.canBePlayed == true && baseItem?.isLiveStream != true
    }

    private var isWatchedBranch: Bool {
        canShowStatusIndicator && isPlayed
    }

    private var isProgressBranch: Bool {
        !isWatchedBranch && hasPlaybackProgress
    }

    private var isUnwatchedBranch: Bool {
        canShowStatusIndicator &&
            !isWatchedBranch &&
            !isProgressBranch
    }

    @ViewBuilder
    private var playOverlay: some View {
        Image(systemName: isPlayed ? "arrow.counterclockwise" : "play.fill")
            .font(.caption2)
            .foregroundStyle(.white)
            .opacity(isFocused ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.18), value: isFocused)
    }

    @ViewBuilder
    private var favoritedOverlay: some View {
        VStack {
            HStack {
                Spacer(minLength: 0)
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(12)
                    .opacity(isFocused ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.18), value: isFocused)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        ProgressView(value: playbackProgress / 100)
            .progressViewStyle(
                FeatureInlineProgressStyle(
                    trackColor: .white.opacity(0.2),
                    fillColor: .white.opacity(1)
                )
            )
            .frame(width: 40)
            .opacity(isFocused ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.18), value: isFocused)
    }

    @ViewBuilder
    private var unwatchedCountOverlay: some View {
        if unplayedIndicatorType == .count,
           let count = baseItem?.userData?.unplayedItemCount,
           count > 0
        {
            Text(count.description)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: 21)
                .frame(minWidth: 21)
                .background(.black.opacity(0.55), in: Capsule())
                .opacity(isFocused ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }

    @ViewBuilder
    private var durationLeftOverlay: some View {
        if let durationLeftLabel {
            Text(durationLeftLabel)
                .font(.caption2)
                .foregroundStyle(.white)
                .opacity(isFocused ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }

    @ViewBuilder
    private var metadataOverlay: some View {
        if baseItem?.type == .episode {
            DotHStack {
                Text(seasonEpisodeLabel)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .opacity(isFocused ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.18), value: isFocused)

                durationLeftOverlay
            }.foregroundStyle(.white).opacity(isFocused ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }

        if baseItem?.type == .movie {
            durationLeftOverlay
        }
    }

    private var shouldShowWatchedOverlay: Bool {
        isWatchedBranch &&
            overlayOptions.contains(.watched)
    }

    private var shouldShowFavorite: Bool {
        overlayOptions.contains(.favorite) && baseItem?.userData?.isFavorite == true
    }

    private var shouldShowProgressOverlay: Bool {
        isProgressBranch &&
            overlayOptions.contains(.progress)
    }

    private var shouldShowUnwatchedOverlay: Bool {
        isUnwatchedBranch &&
            overlayOptions.contains(.unwatched)
    }

    private var shouldShowBottomOverlay: Bool {
        shouldShowWatchedOverlay ||
            shouldShowProgressOverlay ||
            shouldShowUnwatchedOverlay
    }

    @ViewBuilder
    private var bottomBackdrop: some View {
        LinearGradient(
            colors: [
                .clear,
                .black.opacity(0.34),
                .black.opacity(0.5),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.85),
                            .black,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .opacity(isFocused ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: isFocused)
    }

    @ViewBuilder
    private func bottomContent(
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack {
            Spacer(minLength: 0)

            ZStack(alignment: .bottom) {
                bottomBackdrop

                HStack(alignment: .center, spacing: 12) {
                    content()

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var defaultOverlay: some View {
        if shouldShowFavorite {
            favoritedOverlay
        }

        if shouldShowBottomOverlay {
            bottomContent {
                playOverlay

                if shouldShowProgressOverlay {
                    progressOverlay
                } else if shouldShowUnwatchedOverlay {
                    unwatchedCountOverlay
                }

                metadataOverlay
            }
        }
    }

    var body: some View {
        defaultOverlay
    }
}
