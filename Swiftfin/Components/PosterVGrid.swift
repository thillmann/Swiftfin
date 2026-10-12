//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// A native, vertically scrolling poster grid for paged libraries.
struct PosterVGrid<Element: PlatformPoster, Header: View, Content: View>: View {

    private let data: [Element]
    private let columns: [GridItem]
    private let spacing: CGFloat
    private let horizontalPadding: CGFloat
    private let topPadding: CGFloat
    private let posterAspectRatio: CGFloat?
    private let showsHeader: Bool
    private let header: () -> Header
    private let content: (Element) -> Content
    private let onNeedsNextPage: (Element) -> Void
    private let renderID: AnyHashable

    private func stableID(for item: Element) -> AnyHashable? {
        guard item.unwrappedIDHashOrZero != 0 else { return nil }
        return AnyHashable(item.id)
    }

    private var gridItems: [PosterVGridItem<Element>] {
        let idCounts = Dictionary(
            grouping: data.compactMap { stableID(for: $0) },
            by: { $0 }
        )
        .mapValues(\.count)

        return data.enumerated().map { index, item in
            let itemID = stableID(for: item)
            let id: PosterVGridItemID = if let itemID, idCounts[itemID] == 1 {
                .item(itemID)
            } else {
                .offset(index)
            }

            return PosterVGridItem(id: id, index: index, item: item)
        }
    }

    private func pagingTriggerIndex(columnCount: Int) -> Int {
        max(data.count - max(columnCount * 2, 1), 0)
    }

    private func resolvedColumnCount(containerWidth: CGFloat, columns: [GridItem]) -> Int {
        guard columns.count == 1,
              case let .adaptive(minimum, _) = columns[0].size
        else {
            return max(columns.count, 1)
        }

        let availableWidth = max(containerWidth - horizontalPadding * 2, 1)
        return max(
            Int((availableWidth + spacing) / (minimum + spacing)),
            1
        )
    }

    private func fixedPosterSize(containerWidth: CGFloat, columns: [GridItem]) -> CGSize? {
        guard let posterAspectRatio else { return nil }

        let columnCount = resolvedColumnCount(containerWidth: containerWidth, columns: columns)
        let availableWidth = containerWidth
            - horizontalPadding * 2
            - spacing * CGFloat(columnCount - 1)
        let itemWidth = max(availableWidth / CGFloat(columnCount), 1)

        return CGSize(
            width: itemWidth,
            height: itemWidth / posterAspectRatio
        )
    }

    private func resolvedColumns(containerSize: CGSize) -> [GridItem] {
        guard UIDevice.isPad, let posterAspectRatio else { return columns }

        let isLandscapePoster = posterAspectRatio > 1
        let count = if isLandscapePoster {
            containerSize.isLandscape ? 4 : 3
        } else {
            containerSize.isLandscape ? 6 : 5
        }

        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    init(
        data: [Element],
        columns: [GridItem],
        spacing: CGFloat,
        horizontalPadding: CGFloat,
        topPadding: CGFloat = EdgeInsets.edgePadding,
        posterAspectRatio: CGFloat? = nil,
        showsHeader: Bool = false,
        onNeedsNextPage: @escaping (Element) -> Void,
        renderID: AnyHashable,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping (Element) -> Content
    ) {
        self.data = data
        self.columns = columns
        self.spacing = spacing
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.posterAspectRatio = posterAspectRatio
        self.showsHeader = showsHeader
        self.onNeedsNextPage = onNeedsNextPage
        self.renderID = renderID
        self.header = header
        self.content = content
    }

    @ViewBuilder
    private func cells(posterSize: CGSize?, columnCount: Int) -> some View {
        ForEach(gridItems, id: \.id) { gridItem in
            PosterVGridCell(
                gridItem: gridItem,
                isPagingTrigger: gridItem.index >= pagingTriggerIndex(columnCount: columnCount),
                renderID: renderID,
                posterSize: posterSize,
                onNeedsNextPage: onNeedsNextPage,
                content: content
            )
            .equatable()
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let resolvedColumns = resolvedColumns(containerSize: proxy.size)
            let posterSize = fixedPosterSize(containerWidth: proxy.size.width, columns: resolvedColumns)

            ScrollView {
                LazyVGrid(columns: resolvedColumns, spacing: spacing) {
                    if showsHeader {
                        Section {
                            cells(posterSize: posterSize, columnCount: resolvedColumns.count)
                        } header: {
                            header()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, -horizontalPadding)
                                .padding(.bottom, max(topPadding - spacing, 0))
                        }
                    } else {
                        cells(posterSize: posterSize, columnCount: resolvedColumns.count)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, showsHeader ? 0 : topPadding)
                .padding(.bottom, EdgeInsets.edgePadding)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private enum PosterVGridItemID: Hashable {
    case item(AnyHashable)
    case offset(Int)
}

private struct PosterVGridItem<Element> {
    let id: PosterVGridItemID
    let index: Int
    let item: Element
}

private struct PosterVGridCell<Element: PlatformPoster, Content: View>: View, Equatable {

    let gridItem: PosterVGridItem<Element>
    let isPagingTrigger: Bool
    let renderID: AnyHashable
    let posterSize: CGSize?
    let onNeedsNextPage: (Element) -> Void
    let content: (Element) -> Content

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.gridItem.id == rhs.gridItem.id
            && lhs.gridItem.item == rhs.gridItem.item
            && lhs.isPagingTrigger == rhs.isPagingTrigger
            && lhs.renderID == rhs.renderID
            && lhs.posterSize == rhs.posterSize
    }

    var body: some View {
        content(gridItem.item)
            .environment(\.fixedPosterButtonSize, posterSize)
            .onAppear {
                if isPagingTrigger {
                    onNeedsNextPage(gridItem.item)
                }
            }
    }
}
