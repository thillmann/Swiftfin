//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension HomeView {

    struct UpcomingMediaView: View {

        let title: String
        let mediaType: SeerrUpcomingView.MediaType
        let items: [UnifiedMediaResult]
        let onMarkRequested: (SeerrClient.MediaResult) -> Void
        let onPrepareForNavigation: () -> Void

        @Router
        private var router

        @State
        private var pendingRequestItem: SeerrClient.MediaResult?

        var body: some View {
            if SeerrIntegration.isAvailable, items.isNotEmpty {
                PosterHStack(
                    title: title,
                    type: .portrait,
                    items: items
                ) { item in
                    PosterButton(
                        item: item,
                        type: .portrait,
                        usesContextMenu: false
                    ) {
                        select(item)
                    } overlay: {
                        UnifiedMediaResultPosterOverlay(item: item)
                    }
                }
                .trailing {
                    SeeAllPosterButton(
                        type: .portrait,
                        title: L10n.browseAll.localizedCapitalized
                    ) {
                        onPrepareForNavigation()
                        router.route(to: .seerrUpcoming(mediaType: mediaType))
                    }
                }
                .fullScreenCover(item: $pendingRequestItem) { item in
                    SeerrRequestView(item: item) {
                        onMarkRequested(item)
                    }
                }
            }
        }

        private func select(_ item: UnifiedMediaResult) {
            onPrepareForNavigation()

            switch item {
            case let .jellyfin(baseItem):
                router.route(to: .item(item: baseItem))
            case let .seerr(seerrItem):
                pendingRequestItem = seerrItem
            }
        }
    }
}
