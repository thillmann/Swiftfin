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

        @Router
        private var router

        @ObservedObject
        var viewModel: HomeViewModel

        private func seasonEpisodeLabel(for item: BaseItemDto) -> String? {
            if let seasonNumber = item.parentIndexNumber,
               let episodeNumber = item.indexNumber
            {
                return "S\(seasonNumber), E\(episodeNumber)"
            }

            return item.seasonEpisodeLabel
        }

        private func itemSelectorImageSource(for item: BaseItemDto) -> ImageSource {
            if item.type == .episode {
                item.seriesImageSource(
                    .logo,
                    maxWidth: UIScreen.main.bounds.width * 0.4,
                    maxHeight: 200
                )
            } else {
                item.imageSource(
                    .logo,
                    maxWidth: UIScreen.main.bounds.width * 0.4,
                    maxHeight: 200
                )
            }
        }

        var body: some View {
            CinematicItemSelector(items: viewModel.resumeItems.elements) { item in
                router.route(to: .item(item: item))
            }
            .topContent { item in
                ImageView(itemSelectorImageSource(for: item))
                    .placeholder { _ in
                        EmptyView()
                    }
                    .failure {
                        Text(item.displayTitle)
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                    }
                    .edgePadding(.leading)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 200, alignment: .bottomLeading)
            }
            .content { _ in
                EmptyView()
            }
            .posterOverlay(for: BaseItemDto.self) { item in
                VStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.caption2)
                        ProgressView(value: (item.userData?.playedPercentage ?? 0) / 100)
                            .progressViewStyle(
                                FeatureInlineProgressStyle(
                                    trackColor: .white.opacity(0.2),
                                    fillColor: .white
                                )
                            )
                            .frame(width: 40)
                        DotHStack {
                            if item.seasonEpisodeLabel != nil {
                                Text(seasonEpisodeLabel(for: item))
                                    .font(.caption2)
                            }
                            Text(item.progressLabel ?? L10n.continue)
                                .font(.caption2)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            }
        }
    }
}
