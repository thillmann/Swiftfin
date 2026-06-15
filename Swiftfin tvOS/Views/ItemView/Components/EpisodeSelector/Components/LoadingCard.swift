//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension SeriesEpisodeSelector {

    struct LoadingCard: View {

        var body: some View {
            VStack(alignment: .leading) {
                Button {} label: {
                    PosterFallbackContentView(
                        title: nil,
                        systemName: "film"
                    )
                    .posterStyle(.landscape)
                }
                .buttonStyle(.card)
                .disabled(true)
                .posterShadow()

                SeriesEpisodeSelector.EpisodeContent(
                    subHeader: String.random(count: 7 ..< 12),
                    header: String.random(count: 10 ..< 20),
                    content: String.random(count: 20 ..< 80)
                )
                .redacted(reason: .placeholder)
            }
        }
    }
}
