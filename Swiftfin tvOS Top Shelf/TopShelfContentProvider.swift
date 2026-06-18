//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import TVServices

final class TopShelfContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        let entries = TopShelfResumeCache.readEntries()

        guard !entries.isEmpty else { return nil }

        let items = entries.map(makeCarouselItem)
        return TVTopShelfCarouselContent(style: .details, items: items)
    }

    private func makeCarouselItem(
        for entry: TopShelfResumeCache.Entry
    ) -> TVTopShelfCarouselItem {
        let item = TVTopShelfCarouselItem(identifier: entry.id)
        item.title = entry.title
        item.contextTitle = entry.contextTitle
        item.summary = entry.summary
        item.genre = entry.genre
        item.duration = entry.duration ?? 0
        item.creationDate = entry.creationDate

        if let imageURL = entry.imageURL {
            item.setImageURL(imageURL, for: [.screenScale1x, .screenScale2x])
        }

        if let playURL = entry.playURL {
            item.playAction = TVTopShelfAction(url: playURL)
        }

        if let displayURL = entry.displayURL {
            item.displayAction = TVTopShelfAction(url: displayURL)
        }

        return item
    }
}
