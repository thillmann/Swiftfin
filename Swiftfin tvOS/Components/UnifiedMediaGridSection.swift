//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct UnifiedMediaGridSection: View {

    let title: String?
    let items: [UnifiedMediaResult]
    let containerWidth: CGFloat
    let onNeedsNextPage: (UnifiedMediaResult) -> Void
    let onSelect: (UnifiedMediaResult) -> Void

    private let columnCount = 6
    private let gridSpacing: CGFloat = 40
    private let horizontalPadding: CGFloat = 80
    private let posterAspectRatio: CGFloat = 2 / 3

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: gridSpacing),
            count: columnCount
        )
    }

    private var itemWidth: CGFloat {
        let availableWidth = containerWidth - horizontalPadding * 2 - gridSpacing * CGFloat(columnCount - 1)
        return max(availableWidth / CGFloat(columnCount), 1)
    }

    private var itemHeight: CGFloat {
        itemWidth / posterAspectRatio
    }

    init(
        title: String?,
        items: [UnifiedMediaResult],
        containerWidth: CGFloat,
        onNeedsNextPage: @escaping (UnifiedMediaResult) -> Void = { _ in },
        onSelect: @escaping (UnifiedMediaResult) -> Void
    ) {
        self.title = title
        self.items = items
        self.containerWidth = containerWidth
        self.onNeedsNextPage = onNeedsNextPage
        self.onSelect = onSelect
    }

    var body: some View {
        if items.isNotEmpty {
            VStack(alignment: .leading, spacing: 24) {
                if let title {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .accessibility(addTraits: [.isHeader])
                        .padding(.horizontal, horizontalPadding)
                }

                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(items) { item in
                        PosterButton(item: item, type: .portrait) {
                            onSelect(item)
                        } overlay: {
                            UnifiedMediaResultPosterOverlay(item: item)
                        }
                        .frame(width: itemWidth, height: itemHeight)
                        .onAppear {
                            onNeedsNextPage(item)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }
}
