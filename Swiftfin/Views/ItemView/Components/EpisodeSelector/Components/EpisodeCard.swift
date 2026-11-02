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

enum EpisodeCardLayout {
    static let artworkAspectRatio: CGFloat = 1.77
    static let footerHeight: CGFloat = 142
    static let fadeOverlap: CGFloat = 30
    static let itemSpacing: CGFloat = 12
    static let iPadPeekWidth: CGFloat = 32

    static var iPadColumnCount: CGFloat {
        UIApplication.shared.keyWindow?.bounds.size.isLandscape == true ? 4 : 3
    }

    static func height(for itemWidth: CGFloat) -> CGFloat {
        itemWidth / artworkAspectRatio + footerHeight - fadeOverlap
    }

    static func itemWidth(for availableWidth: CGFloat, columns: CGFloat) -> CGFloat {
        if UIDevice.isPad {
            let spacing = columns * itemSpacing
            return max(
                1,
                (availableWidth - EdgeInsets.edgePadding - spacing - iPadPeekWidth) / columns
            )
        }

        let spacing = columns.rounded(.down) * itemSpacing
        return max(1, (availableWidth - EdgeInsets.edgePadding - spacing) / columns)
    }

    static func railHeight(for availableWidth: CGFloat, columns: CGFloat) -> CGFloat {
        height(for: itemWidth(for: availableWidth, columns: columns))
    }
}

extension SeriesEpisodeSelector {

    struct EpisodeCard: View {

        @Namespace
        private var namespace

        @Router
        private var router

        @PlayMedia
        private var playMedia
        @Default(.accentColor)
        private var accentColor

        let episode: BaseItemDto
        let action: ((BaseItemDto) -> Void)?
        let isCurrent: Bool

        init(
            episode: BaseItemDto,
            action: ((BaseItemDto) -> Void)? = nil,
            isCurrent: Bool = false
        ) {
            self.episode = episode
            self.action = action
            self.isCurrent = isCurrent
        }

        private var posterOverlay: some View {
            PosterButtonDefaultOverlay(
                item: episode,
                showsSeasonEpisodeLabel: false,
                leadingBottomContent: AnyView(
                    SeriesEpisodeSelector.EpisodeContent(
                        header: episode.displayTitle,
                        subHeader: episode.episodeLocator ?? .emptyDash,
                        content: episodeContent
                    )
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                ),
                bottomContentHeight: EpisodeCardLayout.footerHeight,
                trailingOverlay: AnyView(
                    PosterButtonOverlayMenu(
                        item: episode,
                        showsSeriesDestination: false
                    )
                )
            )
        }

        private var episodeContent: String {
            if episode.isUnaired {
                episode.airDateLabel ?? L10n.noOverviewAvailable
            } else {
                episode.overview ?? L10n.noOverviewAvailable
            }
        }

        private func play() {
            if let action {
                action(episode)
                return
            }

            playMedia(item: episode)
        }

        private var primaryButtonContent: some View {
            Button(action: play) {
                VStack(spacing: -EpisodeCardLayout.fadeOverlap) {
                    BasePosterButton(
                        item: episode,
                        type: .landscape,
                        imageSources: [episode.imageSource(.primary, maxWidth: 300)],
                        appliesPosterStyle: false
                    ) {
                        PosterFallbackContentView(
                            title: nil,
                            systemName: episode.systemImage
                        )
                    } overlay: {
                        EmptyView()
                    }
                    .aspectRatio(EpisodeCardLayout.artworkAspectRatio, contentMode: .fit)

                    LandscapePosterOverlayExtension(
                        item: episode,
                        imageSources: [episode.imageSource(.primary, maxWidth: 300)],
                        height: EpisodeCardLayout.footerHeight,
                        fadeHeight: EpisodeCardLayout.fadeOverlap,
                        backgroundTintOpacity: 0.12
                    ) {
                        PosterFallbackContentView(
                            title: nil,
                            systemName: episode.systemImage
                        )
                    }
                    .zIndex(1)
                }
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.primary, .secondary)
            .accessibilityLabel(episode.displayTitle)
        }

        @ViewBuilder
        private var primaryButton: some View {
            if #available(iOS 26.0, *) {
                primaryButtonContent
                    .buttonStyle(.plain)
            } else {
                primaryButtonContent
                    .buttonStyle(.card)
            }
        }

        private func posterContent(overlay: some View) -> some View {
            primaryButton
                .overlay { overlay }
        }

        private func posterVisual(overlay: some View) -> some View {
            posterContent(overlay: overlay)
                .contentShape(.contextMenuPreview, Rectangle())
                .posterGlassStyle(.landscape)
        }

        var body: some View {
            posterVisual(overlay: posterOverlay)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(accentColor, lineWidth: 4)
                            .allowsHitTesting(false)
                    }
                }
                .backport
                .matchedTransitionSource(id: "item", in: namespace)
                .posterShadow()
                .contextMenu {
                    PosterButtonMenuActions(item: episode, showsSeriesDestination: false)
                }
        }
    }
}
