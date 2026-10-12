//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension HomeView {

    struct LatestInLibraryView: View {

        @Default(.Customization.latestInLibraryPosterType)
        private var latestInLibraryPosterType

        @Router
        private var router

        @ObservedObject
        var viewModel: LatestInLibraryViewModel

        private var title: String {
            L10n.latestWithString(viewModel.parent?.displayTitle ?? .emptyDash)
        }

        private var isShowingLoadingPlaceholder: Bool {
            viewModel.elements.isEmpty && viewModel.state == .refreshing
        }

        var body: some View {
            ZStack(alignment: .topLeading) {
                if viewModel.elements.isNotEmpty {
                    PlatformPosterHStack(
                        title: title,
                        type: latestInLibraryPosterType,
                        items: viewModel.elements,
                        headerAction: {
                            router.route(to: .library(viewModel: viewModel))
                        }
                    ) { item, namespace in
                        router.route(to: .item(item: item), in: namespace)
                    }
                    .transition(.opacity)
                } else if isShowingLoadingPlaceholder {
                    PosterHStackLoadingPlaceholder(
                        title: title,
                        type: latestInLibraryPosterType,
                        idPrefix: "latest-\(viewModel.parent?.id ?? "library")"
                    )
                    .transition(.opacity)
                }
            }
            .animation(PosterLoadingPlaceholder.transitionAnimation, value: isShowingLoadingPlaceholder)
        }
    }
}
