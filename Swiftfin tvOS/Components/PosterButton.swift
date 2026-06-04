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

struct PosterOverlayComponents: OptionSet {

    let rawValue: Int

    static let playIcon = PosterOverlayComponents(rawValue: 1 << 0)
    static let progressBar = PosterOverlayComponents(rawValue: 1 << 1)
    static let seasonEpisodeLabel = PosterOverlayComponents(rawValue: 1 << 2)
    static let durationLeft = PosterOverlayComponents(rawValue: 1 << 3)
    static let favoriteIcon = PosterOverlayComponents(rawValue: 1 << 4)

    static let `default`: PosterOverlayComponents = [
        .progressBar,
        .favoriteIcon,
    ]

    static let resume: PosterOverlayComponents = [
        .playIcon,
        .progressBar,
        .seasonEpisodeLabel,
        .durationLeft,
        .favoriteIcon,
    ]
}

extension EnvironmentValues {

    @Entry
    var posterOverlayComponents: PosterOverlayComponents = .default
}

extension View {

    func posterOverlayComponents(_ components: PosterOverlayComponents) -> some View {
        environment(\.posterOverlayComponents, components)
    }
}

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

    struct DefaultOverlay: View {

        @Default(.Customization.Indicators.showUnplayed)
        private var showUnplayed

        @Default(.Customization.Indicators.showFavorited)
        private var showFavorited
        @Default(.Customization.Indicators.showProgress)
        private var showProgress

        @Environment(\.isPosterFocused)
        private var isPosterFocused

        @Environment(\.posterOverlayComponents)
        private var components

        let item: Item

        private let gradientHeight: CGFloat = 68

        private var baseItem: BaseItemDto? {
            item as? BaseItemDto
        }

        private var overlayOpacity: Double {
            isPosterFocused ? 1 : 0.35
        }

        private var favoriteOpacity: Double {
            isPosterFocused ? 1 : 0.65
        }

        private var isPlayed: Bool {
            baseItem?.userData?.isPlayed == true ||
                (baseItem?.userData?.playedPercentage ?? 0) >= 100
        }

        private var playedPercentage: Double {
            (baseItem?.userData?.playedPercentage ?? 0) / 100
        }

        private var hasPlaybackProgress: Bool {
            (baseItem?.userData?.playbackPositionTicks ?? 0) > 0
        }

        private var shouldShowPlayIcon: Bool {
            guard components.contains(.playIcon),
                  let baseItem,
                  baseItem.canBePlayed,
                  !baseItem.isLiveStream
            else {
                return false
            }

            return isPlayed || showUnplayed != .none || components.contains(.durationLeft)
        }

        private var playIconSystemName: String {
            isPlayed ? "arrow.counterclockwise" : "play.fill"
        }

        private var shouldShowProgressBar: Bool {
            components.contains(.progressBar) &&
                showProgress &&
                hasPlaybackProgress &&
                !isPlayed
        }

        private var seasonEpisodeLabel: String? {
            guard components.contains(.seasonEpisodeLabel),
                  let baseItem
            else {
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
            guard components.contains(.durationLeft) else {
                return nil
            }

            if hasPlaybackProgress, !isPlayed, let progressLabel = baseItem?.progressLabel {
                return progressLabel
            }

            return baseItem?.runTimeLabel
        }

        private var shouldShowFavoriteIcon: Bool {
            components.contains(.favoriteIcon) &&
                showFavorited &&
                baseItem?.userData?.isFavorite == true
        }

        private var hasBottomContent: Bool {
            shouldShowPlayIcon ||
                shouldShowProgressBar ||
                seasonEpisodeLabel != nil ||
                durationLeftLabel != nil
        }

        @ViewBuilder
        private var bottomBackdrop: some View {
            if hasBottomContent {
                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.34 * overlayOpacity),
                        .black.opacity(0.5 * overlayOpacity),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxWidth: .infinity)
                .frame(height: gradientHeight)
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
                        .opacity(overlayOpacity)
                }
            }
        }

        @ViewBuilder
        private var favoriteIcon: some View {
            if shouldShowFavoriteIcon {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(12)
                    .opacity(favoriteOpacity)
            }
        }

        @ViewBuilder
        private var metadataLabels: some View {
            if seasonEpisodeLabel != nil || durationLeftLabel != nil {
                DotHStack {
                    if let seasonEpisodeLabel {
                        Text(seasonEpisodeLabel)
                    }

                    if let durationLeftLabel {
                        Text(durationLeftLabel)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(overlayOpacity))
                .lineLimit(1)
            }
        }

        @ViewBuilder
        private var bottomContent: some View {
            if hasBottomContent {
                HStack(spacing: 12) {
                    if shouldShowPlayIcon {
                        Image(systemName: playIconSystemName)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(overlayOpacity))
                    }

                    if shouldShowProgressBar {
                        ProgressView(value: playedPercentage)
                            .progressViewStyle(
                                FeatureInlineProgressStyle(
                                    trackColor: .white.opacity(0.2 * overlayOpacity),
                                    fillColor: .white.opacity(overlayOpacity)
                                )
                            )
                            .frame(width: 40)
                    }

                    metadataLabels

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }

        var body: some View {
            ZStack(alignment: .bottom) {
                bottomBackdrop

                bottomContent

                VStack {
                    HStack {
                        Spacer()

                        favoriteIcon
                    }

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.18), value: isPosterFocused)
        }
    }
}
