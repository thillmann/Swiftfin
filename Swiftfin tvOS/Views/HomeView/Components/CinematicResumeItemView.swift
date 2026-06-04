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
            .posterOverlayComponents(.resume)
        }
    }
}
