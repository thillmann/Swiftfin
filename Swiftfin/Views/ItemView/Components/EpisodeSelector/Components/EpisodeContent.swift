//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension SeriesEpisodeSelector {

    struct EpisodeContent: View {

        let header: String
        let subHeader: String
        let content: String

        @ViewBuilder
        private var subHeaderView: some View {
            Text(subHeader)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .textCase(.uppercase)
        }

        @ViewBuilder
        private var headerView: some View {
            Text(header)
                .font(.headline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .multilineTextAlignment(.leading)
        }

        @ViewBuilder
        private var contentView: some View {
            // An empty `Text` does not occupy a line, even when `reservesSpace`
            // is set. Use a non-breaking space so cards without an overview keep
            // the footer actions aligned with cards that have one.
            Text(content.isEmpty ? "\u{00A0}" : content)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.leading)
                .lineLimit(3, reservesSpace: true)
                .lineSpacing(1)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                subHeaderView
                    .padding(.bottom, 3)

                headerView
                    .padding(.bottom, 5)

                contentView
            }
        }
    }
}
