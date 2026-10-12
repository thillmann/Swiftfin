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

    struct MovieItemContentView: View {

        @ObservedObject
        var viewModel: MovieItemViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: PlatformItemView.detailSectionSpacing) {

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
