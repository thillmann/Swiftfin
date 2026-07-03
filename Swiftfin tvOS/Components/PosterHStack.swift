//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// TODO: trailing content refactor?

struct PosterHStack<Element: Poster, Data: Collection, PosterButtonView: View>: View where Data.Element == Element, Data.Index == Int {

    private var data: Data
    private var title: String?
    private var type: PosterDisplayType
    private var itemContentAspectRatio: CGFloat?
    private var posterButton: (Element) -> PosterButtonView
    private var trailingContent: (() -> AnyView)?

    @State
    private var contentSize: CGSize = .zero

    private var aspectRatio: CGFloat {
        switch type {
        case .landscape:
            1.77
        case .portrait:
            2 / 3
        case .square:
            1
        }
    }

    private var columnCount: CGFloat {
        type == .landscape ? 4 : 6
    }

    private var horizontalPadding: CGFloat {
        EdgeInsets.edgePadding
    }

    private var itemSpacing: CGFloat {
        EdgeInsets.edgePadding - 40
    }

    private var verticalPadding: CGFloat {
        20
    }

    private var itemWidth: CGFloat {
        let availableWidth = contentSize.width > 0 ? contentSize.width : UIScreen.main.bounds.width
        let width = (
            availableWidth - horizontalPadding * 2 - itemSpacing * (columnCount - 1)
        ) / columnCount

        return max(width, 1)
    }

    private var itemHeight: CGFloat {
        itemWidth / (itemContentAspectRatio ?? aspectRatio)
    }

    private var rowHeight: CGFloat {
        itemHeight + verticalPadding * 2
    }

    private var visibleData: [Element] {
        Array(data.prefix(20))
    }

    private var visibleItems: [PosterHStackItem<Element>] {
        let idCounts = Dictionary(
            grouping: visibleData.map(\.unwrappedIDHashOrZero).filter { $0 != 0 },
            by: { $0 }
        )
        .mapValues(\.count)

        return visibleData.enumerated().map { offset, item in
            let itemID = item.unwrappedIDHashOrZero
            let id: PosterHStackItemID = if itemID != 0, idCounts[itemID] == 1 {
                .item(itemID)
            } else {
                .offset(offset)
            }

            return PosterHStackItem(id: id, item: item)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            if let title {
                HStack {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .accessibility(addTraits: [.isHeader])
                        .padding(.leading, 80)

                    Spacer()
                }
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: itemSpacing) {
                    ForEach(visibleItems, id: \.id) { visibleItem in
                        posterButton(visibleItem.item)
                            .frame(width: itemWidth, height: itemHeight)
                    }

                    if let trailingContent {
                        trailingContent()
                            .frame(width: itemWidth, height: itemHeight)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
            }
            .frame(height: rowHeight)
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
        .trackingSize($contentSize)
        .focusSection()
    }
}

private enum PosterHStackItemID: Hashable {
    case item(Int)
    case offset(Int)
}

private struct PosterHStackItem<Element> {
    let id: PosterHStackItemID
    let item: Element
}

extension PosterHStack where PosterButtonView == PosterButton<Element, PosterButtonDefaultOverlay<Element>, PosterFallbackContentView> {

    init(
        title: String? = nil,
        type: PosterDisplayType,
        items: Data,
        overlayOptions: PosterButtonOverlayOptions = .default,
        unplayedIndicatorType: UnplayedIndicatorType = .none,
        action: @escaping (Element) -> Void
    ) {
        self.init(
            data: items,
            title: title,
            type: type,
            itemContentAspectRatio: nil,
            posterButton: { item in
                PosterButton(
                    item: item,
                    type: type,
                    overlayOptions: overlayOptions,
                    unplayedIndicatorType: unplayedIndicatorType
                ) {
                    action(item)
                }
            },
            trailingContent: nil
        )
    }
}

extension PosterHStack {

    init(
        title: String? = nil,
        type: PosterDisplayType,
        items: Data,
        @ViewBuilder posterButton: @escaping (Element) -> PosterButtonView
    ) {
        self.init(
            data: items,
            title: title,
            type: type,
            itemContentAspectRatio: nil,
            posterButton: posterButton,
            trailingContent: nil
        )
    }

    func trailing<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> Self {
        copy(modifying: \.trailingContent, with: Optional.some { AnyView(content()) })
    }

    func itemContentAspectRatio(_ aspectRatio: CGFloat) -> Self {
        copy(modifying: \.itemContentAspectRatio, with: aspectRatio)
    }
}
