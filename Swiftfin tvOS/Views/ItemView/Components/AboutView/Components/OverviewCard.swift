//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension ItemView.AboutView {

    struct OverviewCard: View {

        @Router
        private var router

        let item: BaseItemDto

        private var genres: String? {
            guard let genres = item.genres, genres.isNotEmpty else { return nil }
            return genres.joined(separator: ", ")
        }

        var body: some View {
            Button {
                router.route(to: .itemOverview(item: item))
            } label: {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayTitle)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let genres {
                            Text(genres)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }

                    Text(item.overview ?? L10n.noOverviewAvailable)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(7)
                        .truncationMode(.tail)
                }
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 34)
                .frame(width: 900, height: 405, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.white.opacity(0.12))
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .containerShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.card)
        }
    }
}
