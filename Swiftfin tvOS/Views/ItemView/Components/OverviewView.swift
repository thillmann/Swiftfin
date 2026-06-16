//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// TODO: have items provide labeled attributes
// TODO: don't layout `VStack` if no data

extension ItemView {

    struct OverviewView: View {

        let item: BaseItemDto
        private var overviewLineLimit: Int?
        private var taglineLineLimit: Int?

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {

                if let birthday = item.birthday?.formatted(date: .long, time: .omitted) {
                    LabeledContent(
                        L10n.born,
                        value: birthday
                    )
                }

                if let deathday = item.deathday?.formatted(date: .long, time: .omitted) {
                    LabeledContent(
                        L10n.died,
                        value: deathday
                    )
                }

                if let birthplace = item.birthplace {
                    LabeledContent(
                        L10n.birthplace,
                        value: birthplace
                    )
                }

                if let firstTagline = item.taglines?.first {
                    Text(firstTagline)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)
                        .lineLimit(taglineLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let itemOverview = item.overview {
                    if item.type == .episode {
                        episodeOverviewText(itemOverview)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.leading)
                            .lineLimit(overviewLineLimit)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(itemOverview)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.leading)
                            .lineLimit(overviewLineLimit)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.footnote)
            .labeledContentStyle(.itemAttribute)
        }

        private func episodeOverviewText(_ overview: String) -> Text {
            let titleText = Text("\(item.displayTitle): ")
                .fontWeight(.semibold)
            let overviewText = Text(overview)

            guard let seasonEpisodeLabel = item.seasonEpisodeLabel else {
                return titleText + overviewText
            }

            return Text("\(seasonEpisodeLabel) • ")
                .fontWeight(.semibold) +
                titleText +
                overviewText
        }
    }
}

extension ItemView.OverviewView {

    init(item: BaseItemDto) {
        self.init(
            item: item,
            overviewLineLimit: nil,
            taglineLineLimit: nil
        )
    }

    func overviewLineLimit(_ limit: Int) -> Self {
        copy(modifying: \.overviewLineLimit, with: limit)
    }

    func taglineLineLimit(_ limit: Int) -> Self {
        copy(modifying: \.taglineLineLimit, with: limit)
    }
}
