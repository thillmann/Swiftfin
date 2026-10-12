//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension PlatformItemView {

    struct SeriesItemContentView: View {

        @ObservedObject
        var viewModel: SeriesItemViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: PlatformItemView.detailSectionSpacing) {

                // MARK: Episodes

                switch viewModel.seasonsState {
                case .initial, .loading:
                    SeriesEpisodeSelector.LoadingSelector()
                case .content where viewModel.seasons.isNotEmpty:
                    SeriesEpisodeSelector(viewModel: viewModel)
                case .error:
                    Button {
                        viewModel.send(.refresh)
                    } label: {
                        Label(L10n.retry, systemImage: "arrow.clockwise")
                    }
                    .edgePadding(.horizontal)
                case .content:
                    EmptyView()
                }

                // MARK: Recommended

                if viewModel.similarItems.isNotEmpty {
                    PlatformItemView.SimilarItemsHStack(items: viewModel.similarItems)
                }

                // MARK: Cast and Crew

                if let castAndCrew = viewModel.item.people,
                   castAndCrew.isNotEmpty
                {
                    PlatformItemView.CastAndCrewHStack(people: castAndCrew)
                }

                PlatformItemView.AboutView(viewModel: viewModel)
            }
        }
    }
}
