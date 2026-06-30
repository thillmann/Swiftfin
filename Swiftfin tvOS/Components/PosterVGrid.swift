//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct PosterVGrid<Element: Poster>: View {

    private let data: [Element]

    private let layout: LibraryDisplayType
    private let columnCount: Int
    private let posterType: PosterDisplayType
    private let overlayOptions: PosterButtonOverlayOptions
    private let unplayedIndicatorType: UnplayedIndicatorType
    private let onNeedsNextPage: (Element) -> Void
    private let onSelect: (Element) -> Void

    private var gridSpacing: CGFloat {
        if layout == .grid {
            40.0
        } else {
            20.0
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: gridSpacing),
            count: columnCount
        )
    }

    private var horizontalPadding: CGFloat {
        80
    }

    private var topPadding: CGFloat {
        120
    }

    private var posterAspectRatio: CGFloat {
        switch posterType {
        case .landscape:
            1.77
        case .portrait:
            2 / 3
        case .square:
            1
        }
    }

    private var gridItems: [PosterVGridItem<Element>] {
        let idCounts = Dictionary(
            grouping: data.map(\.unwrappedIDHashOrZero).filter { $0 != 0 },
            by: { $0 }
        )
        .mapValues(\.count)

        return data.enumerated().map { offset, item in
            let itemID = item.unwrappedIDHashOrZero
            let id: PosterVGridItemID = if itemID != 0, idCounts[itemID] == 1 {
                .item(itemID)
            } else {
                .offset(offset)
            }

            return PosterVGridItem(id: id, item: item)
        }
    }

    init(
        data: [Element],
        layout: LibraryDisplayType = .grid,
        posterType: PosterDisplayType = .portrait,
        overlayOptions: PosterButtonOverlayOptions = .default,
        unplayedIndicatorType: UnplayedIndicatorType = .none,
        onNeedsNextPage: @escaping (Element) -> Void = { _ in },
        onSelect: @escaping (Element) -> Void
    ) {
        self.data = data
        self.layout = layout
        self.posterType = posterType
        self.overlayOptions = overlayOptions
        self.unplayedIndicatorType = unplayedIndicatorType
        self.columnCount = 1
        self.onNeedsNextPage = onNeedsNextPage
        self.onSelect = onSelect
    }

    init(
        data: [Element],
        layout: LibraryDisplayType = .grid,
        posterType: PosterDisplayType = .portrait,
        columnCount: Int,
        overlayOptions: PosterButtonOverlayOptions = .default,
        unplayedIndicatorType: UnplayedIndicatorType = .none,
        onNeedsNextPage: @escaping (Element) -> Void = { _ in },
        onSelect: @escaping (Element) -> Void
    ) {
        self.data = data
        self.layout = layout
        self.posterType = posterType
        self.overlayOptions = overlayOptions
        self.unplayedIndicatorType = unplayedIndicatorType
        self.columnCount = columnCount
        self.onNeedsNextPage = onNeedsNextPage
        self.onSelect = onSelect
    }

    private func itemWidth(containerWidth: CGFloat) -> CGFloat {
        let availableWidth = containerWidth - horizontalPadding * 2 - gridSpacing * CGFloat(columnCount - 1)
        return max(availableWidth / CGFloat(columnCount), 1)
    }

    private func itemHeight(containerWidth: CGFloat) -> CGFloat {
        itemWidth(containerWidth: containerWidth) / posterAspectRatio
    }

    private func gridCell(for item: Element, containerWidth: CGFloat) -> some View {
        Group {
            if let unifiedItem = item as? UnifiedMediaResult {
                PosterButton(item: unifiedItem, type: posterType) {
                    onSelect(item)
                } overlay: {
                    UnifiedMediaResultPosterOverlay(item: unifiedItem)
                }
            } else {
                PosterButton(
                    item: item,
                    type: posterType,
                    overlayOptions: overlayOptions,
                    unplayedIndicatorType: unplayedIndicatorType
                ) {
                    onSelect(item)
                }
            }
        }
        .frame(
            width: itemWidth(containerWidth: containerWidth),
            height: itemHeight(containerWidth: containerWidth)
        )
    }

    private func listCell(for item: Element) -> some View {
        Button {
            onSelect(item)
        } label: {
            HStack(spacing: 20) {
                PosterImage(
                    item: item,
                    type: .landscape
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: 160)

                VStack(spacing: 8) {
                    Text(item.displayTitle)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func cell(for item: Element, containerWidth: CGFloat) -> some View {
        if layout == .grid {
            gridCell(for: item, containerWidth: containerWidth)
        } else {
            listCell(for: item)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(gridItems, id: \.id) { gridItem in
                        cell(for: gridItem.item, containerWidth: proxy.size.width)
                            .onAppear {
                                onNeedsNextPage(gridItem.item)
                            }
                    }
                }
                .padding(horizontalPadding)
                .padding(.top, topPadding)
            }
        }
    }
}

private enum PosterVGridItemID: Hashable {
    case item(Int)
    case offset(Int)
}

private struct PosterVGridItem<Element> {
    let id: PosterVGridItemID
    let item: Element
}
