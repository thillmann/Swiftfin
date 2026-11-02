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

extension HomeView {

    struct NextUpView: View {

        @Default(.Customization.nextUpPosterType)
        private var nextUpPosterType

        @Router
        private var router

        @PlayMedia
        private var playMedia

        @ObservedObject
        var viewModel: NextUpLibraryViewModel

        private var isShowingLoadingPlaceholder: Bool {
            viewModel.elements.isEmpty && viewModel.state == .refreshing
        }

        var body: some View {
            ZStack(alignment: .topLeading) {
                if viewModel.elements.isNotEmpty {
                    PlatformPosterHStack(
                        title: L10n.nextUp,
                        type: nextUpPosterType,
                        items: viewModel.elements,
                        headerAction: {
                            router.route(to: .library(viewModel: viewModel))
                        }
                    ) { item, _ in
                        playMedia(item: item)
                    } label: { item in
                        if item.type == .episode {
                            PosterButtonEpisodeContentSubtitleContent(item: item)
                        } else {
                            PosterButtonTitleSubtitleContentView(item: item)
                        }
                    }
                    .transition(.opacity)
                } else if isShowingLoadingPlaceholder {
                    PosterHStackLoadingPlaceholder(
                        title: L10n.nextUp,
                        type: nextUpPosterType,
                        idPrefix: "next-up"
                    )
                    .transition(.opacity)
                }
            }
            .animation(PosterLoadingPlaceholder.transitionAnimation, value: isShowingLoadingPlaceholder)
        }
    }
}
