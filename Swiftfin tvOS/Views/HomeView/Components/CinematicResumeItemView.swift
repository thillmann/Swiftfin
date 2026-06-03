//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension HomeView {

    struct CinematicResumeView: View {

        private let logoHeight: CGFloat = 200
        private let logoWidth = UIScreen.main.bounds.width * 0.4

        @Router
        private var router

        @ObservedObject
        var viewModel: HomeViewModel

        private func itemSelectorImageSource(for item: BaseItemDto) -> ImageSource {
            if item.type == .episode {
                item.seriesImageSource(
                    .logo,
                    maxWidth: logoWidth,
                    maxHeight: logoHeight
                )
            } else {
                item.imageSource(
                    .logo,
                    maxWidth: logoWidth,
                    maxHeight: logoHeight
                )
            }
        }

        var body: some View {
            CinematicItemSelector(items: viewModel.resumeItems.elements) { item in
                router.route(to: .item(item: item))
            }
            .topContent { item in
                ZStack(alignment: .bottomLeading) {
                    Color.clear

                    ImageView(itemSelectorImageSource(for: item))
                        .placeholder { _ in
                            Color.clear
                        }
                        .failure {
                            Text(item.displayTitle)
                                .font(.largeTitle)
                                .fontWeight(.semibold)
                                .frame(maxWidth: logoWidth, alignment: .leading)
                        }
                        .aspectRatio(contentMode: .fit)
                }
                .edgePadding(.leading)
                .frame(width: logoWidth, height: logoHeight, alignment: .bottomLeading)
            }
            .content { _ in
                EmptyView()
            }
            .posterOverlay(for: BaseItemDto.self) { item in
                CinematicResumeOverlay(item: item)
            }
        }
    }
}

private struct CinematicResumeOverlay: View {

    private let gradientHeight: CGFloat = 68

    @Environment(\.isPosterFocused)
    private var isPosterFocused

    @State
    private var overlayOpacity = 0.35

    let item: BaseItemDto

    private var targetOverlayOpacity: Double {
        isPosterFocused ? 1 : 0.35
    }

    private var seasonEpisodeLabel: String? {
        if let seasonNumber = item.parentIndexNumber,
           let episodeNumber = item.indexNumber
        {
            return "S\(seasonNumber), E\(episodeNumber)"
        }

        return item.seasonEpisodeLabel
    }

    var body: some View {
        ZStack(alignment: .bottom) {
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

            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(overlayOpacity))

                ProgressView(value: (item.userData?.playedPercentage ?? 0) / 100)
                    .progressViewStyle(
                        FeatureInlineProgressStyle(
                            trackColor: .white.opacity(0.2 * overlayOpacity),
                            fillColor: .white.opacity(overlayOpacity)
                        )
                    )
                    .frame(width: 40)

                DotHStack {
                    if let seasonEpisodeLabel {
                        Text(seasonEpisodeLabel)
                            .font(.caption2)
                    }

                    Text(item.progressLabel ?? L10n.continue)
                        .font(.caption2)
                }
                .foregroundStyle(.white.opacity(overlayOpacity))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear {
            overlayOpacity = targetOverlayOpacity
        }
        .onChange(of: isPosterFocused) { _, _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                overlayOpacity = targetOverlayOpacity
            }
        }
    }
}
