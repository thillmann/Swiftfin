//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct PlatformPosterHStack<Element: PlatformPoster, Data: Collection, PosterButtonView: View>: View where Data.Element == Element,
Data.Index == Int {
    private var data: Data
    private var header: AnyView?
    private var title: String?
    private var type: PosterDisplayType
    private var itemColumnCount: CGFloat?
    private var itemContentAspectRatio: CGFloat?
    private var itemLabelHeight: CGFloat?
    private var posterButton: (Element) -> PosterButtonView
    private var trailingContent: (() -> AnyView)?

    @State
    private var contentSize: CGSize = .zero
    #if !os(tvOS)
    @Default(.Customization.showPosterLabels)
    private var showPosterLabels
    #endif

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
        #if os(tvOS)
        type == .landscape ? 4 : 6
        #else
        if UIDevice.isPad {
            let isLandscape = UIApplication.shared.keyWindow?.bounds.size.isLandscape == true
            return type == .landscape
                ? (isLandscape ? 4 : 3)
                : (isLandscape ? 6 : 5)
        }

        if let itemColumnCount {
            return itemColumnCount
        }

        if UIDevice.isPhone {
            return type == .landscape ? 4 / 3 : 3
        } else {
            return type == .landscape ? 4 : 6
        }
        #endif
    }

    private var horizontalPadding: CGFloat {
        EdgeInsets.edgePadding
    }

    private var itemSpacing: CGFloat {
        #if os(tvOS)
        EdgeInsets.edgePadding - 40
        #else
        max(12, EdgeInsets.edgePadding / 2)
        #endif
    }

    #if os(tvOS)
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
    #else
    private func itemWidth(for availableWidth: CGFloat) -> CGFloat {
        if UIDevice.isPad {
            let peekWidth: CGFloat = 32
            let width = availableWidth
                - horizontalPadding
                - itemSpacing * columnCount
                - peekWidth
            return max(1, width / columnCount)
        }

        let width = availableWidth - horizontalPadding * 2 - itemSpacing * (columnCount - 1)
        return max(1, width / columnCount)
    }

    private func railHeight(for availableWidth: CGFloat) -> CGFloat {
        itemWidth(for: availableWidth) / (itemContentAspectRatio ?? aspectRatio)
            + landscapeOverlayHeight
            + (itemLabelHeight ?? (showPosterLabels ? 42 : 0))
    }

    private var landscapeOverlayHeight: CGFloat {
        type == .landscape ? PosterButtonLayout.landscapeFooterHeight : 0
    }

    private var railAvailableWidth: CGFloat {
        if UIDevice.isPad, contentSize.width > 0 {
            return contentSize.width
        }

        return UIScreen.main.bounds.width
    }
    #endif

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

    #if os(tvOS)
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
    #else
    @ViewBuilder
    private var stack: some View {
        GeometryReader { proxy in
            let itemWidth = itemWidth(for: proxy.size.width)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: itemSpacing) {
                    ForEach(visibleItems, id: \.id) { visibleItem in
                        posterButton(visibleItem.item)
                            .frame(width: itemWidth, alignment: .top)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, horizontalPadding)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .frame(height: railHeight(for: proxy.size.width), alignment: .top)
        }
        .frame(height: railHeight(for: railAvailableWidth), alignment: .top)
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if let header {
                    header
                }

                Spacer()

                if let trailingContent {
                    trailingContent()
                }
            }
            .edgePadding(.horizontal)

            stack
        }
        .if(UIDevice.isPad) { view in
            view.trackingSize($contentSize)
        }
    }
    #endif
}

private enum PosterHStackItemID: Hashable {
    case item(Int)
    case offset(Int)
}

private struct PosterHStackItem<Element> {
    let id: PosterHStackItemID
    let item: Element
}

extension PlatformPosterHStack where PosterButtonView == PlatformPosterButton<
    Element,
    PosterButtonDefaultOverlay<Element>,
    PosterFallbackContentView
> {

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
            header: nil,
            title: title,
            type: type,
            itemColumnCount: nil,
            itemContentAspectRatio: nil,
            itemLabelHeight: nil,
            posterButton: { item in
                PlatformPosterButton(
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

    #if os(iOS)
    init(
        title: String? = nil,
        type: PosterDisplayType,
        items: Data,
        headerAction: (() -> Void)? = nil,
        action: @escaping (Element, Namespace.ID) -> Void,
        @ViewBuilder label: @escaping (Element) -> any View = { PosterButtonTitleSubtitleContentView(item: $0) }
    ) {
        self.init(
            data: items,
            header: AnyView(PosterHStackDefaultHeader(title: title, action: headerAction)),
            title: title,
            type: type,
            itemColumnCount: nil,
            itemContentAspectRatio: nil,
            itemLabelHeight: nil,
            posterButton: { item in
                PlatformPosterButton(
                    item: item,
                    type: type
                ) { namespace in
                    action(item, namespace)
                } label: {
                    label(item).eraseToAnyView()
                }
            },
            trailingContent: nil
        )
    }
    #endif
}

extension PlatformPosterHStack {

    init(
        title: String? = nil,
        type: PosterDisplayType,
        items: Data,
        headerAction: (() -> Void)? = nil,
        @ViewBuilder posterButton: @escaping (Element) -> PosterButtonView
    ) {
        #if os(iOS)
        let header = AnyView(PosterHStackDefaultHeader(title: title, action: headerAction))
        #else
        let header: AnyView? = nil
        #endif

        self.init(
            data: items,
            header: header,
            title: title,
            type: type,
            itemColumnCount: nil,
            itemContentAspectRatio: nil,
            itemLabelHeight: nil,
            posterButton: posterButton,
            trailingContent: nil
        )
    }

    func trailing(@ViewBuilder _ content: @escaping () -> some View) -> Self {
        copy(modifying: \.trailingContent, with: Optional.some { AnyView(content()) })
    }

    func itemContentAspectRatio(_ aspectRatio: CGFloat) -> Self {
        copy(modifying: \.itemContentAspectRatio, with: aspectRatio)
    }

    func itemColumnCount(_ count: CGFloat) -> Self {
        copy(modifying: \.itemColumnCount, with: count)
    }

    func itemLabelHeight(_ height: CGFloat) -> Self {
        copy(modifying: \.itemLabelHeight, with: height)
    }
}

private struct PosterHStackDefaultHeader: View {

    let title: String?
    let action: (() -> Void)?

    var body: some View {
        if let title {
            if let action {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Text(title)
                            .foregroundStyle(.primary)

                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .font(.title2)
                .fontWeight(.semibold)
                .accessibility(addTraits: [.isHeader])
            } else {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibility(addTraits: [.isHeader])
            }
        }
    }
}
