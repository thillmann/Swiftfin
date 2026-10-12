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

    struct RecentlyAddedView: View {

        @Default(.Customization.recentlyAddedPosterType)
        private var recentlyAddedPosterType

        @Router
        private var router

        @ObservedObject
        var viewModel: RecentlyAddedLibraryViewModel

        private var isShowingLoadingPlaceholder: Bool {
            viewModel.elements.isEmpty && viewModel.state == .refreshing
        }

        var body: some View {
            ZStack(alignment: .topLeading) {
                if viewModel.elements.isNotEmpty {
                    PlatformPosterHStack(
                        title: L10n.recentlyAdded.localizedCapitalized,
                        type: recentlyAddedPosterType,
                        items: viewModel.elements,
                        headerAction: {
                            // Give a new view model because we don't want to
                            // keep paginated items on the home view model
                            let viewModel = RecentlyAddedLibraryViewModel()
                            router.route(to: .library(viewModel: viewModel))
                        }
                    ) { item, namespace in
                        router.route(to: .item(item: item), in: namespace)
                    }
                    .transition(.opacity)
                } else if isShowingLoadingPlaceholder {
                    PosterHStackLoadingPlaceholder(
                        title: L10n.recentlyAdded.localizedCapitalized,
                        type: recentlyAddedPosterType,
                        idPrefix: "recently-added"
                    )
                    .transition(.opacity)
                }
            }
            .animation(PosterLoadingPlaceholder.transitionAnimation, value: isShowingLoadingPlaceholder)
        }
    }
}
