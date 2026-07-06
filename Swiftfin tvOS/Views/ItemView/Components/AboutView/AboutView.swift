//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension ItemView {

    struct AboutView: View {

        @ObservedObject
        var viewModel: ItemViewModel

        private var mediaSourceCount: Int {
            viewModel.item.mediaSources?.count ?? 0
        }

        private var selectedMediaSource: MediaSourceInfo? {
            guard let mediaSources = viewModel.item.mediaSources else { return nil }

            guard let selectedMediaSource = viewModel.selectedMediaSource else {
                return mediaSources.first
            }

            return mediaSources.first { mediaSource in
                mediaSourcesMatch(mediaSource, selectedMediaSource)
            } ?? mediaSources.first
        }

        private func mediaSourcesMatch(_ lhs: MediaSourceInfo, _ rhs: MediaSourceInfo) -> Bool {
            if let lhsID = lhs.id,
               let rhsID = rhs.id
            {
                return lhsID == rhsID
            }

            return lhs == rhs
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {

                Text(L10n.about)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .accessibility(addTraits: [.isHeader])
                    .padding(.leading, 80)

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 30) {
                        ImageCard(viewModel: viewModel)

                        OverviewCard(item: viewModel.item)

                        if viewModel.item.hasRatings {
                            RatingsCard(item: viewModel.item)
                        }

                        if let selectedMediaSource {
                            MediaSourcesCard(
                                subtitle: mediaSourceCount > 1 ? selectedMediaSource.displayTitle : nil,
                                source: selectedMediaSource
                            )
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 40)
                }
                .scrollClipDisabled()
            }
            .focusSection()
        }
    }
}
