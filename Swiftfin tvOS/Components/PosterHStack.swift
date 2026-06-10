//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// TODO: trailing content refactor?

struct PosterHStack<Element: Poster, Data: Collection>: View where Data.Element == Element, Data.Index == Int {

    typealias PosterButtonBuilder = (
        Element,
        @escaping () -> Void,
        @escaping () -> AnyView
    ) -> AnyView

    private var data: Data
    private var title: String?
    private var type: PosterDisplayType
    private var itemContentAspectRatio: CGFloat?
    private var label: (Element) -> any View
    private var posterButton: PosterButtonBuilder
    private var trailingContent: () -> any View
    private let action: (Element) -> Void

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
                    ForEach(visibleData, id: \.unwrappedIDHashOrZero) { item in
                        posterButton(item, {
                            action(item)
                        }, {
                            label(item).eraseToAnyView()
                        })
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

extension PosterHStack {

    init(
        title: String? = nil,
        type: PosterDisplayType,
        items: Data,
        action: @escaping (Element) -> Void,
        @ViewBuilder label: @escaping (Element) -> any View = { _ in EmptyView() },
        posterButton: PosterButtonBuilder? = nil
    ) {
        self.init(
            data: items,
            title: title,
            type: type,
            itemContentAspectRatio: nil,
            label: label,
            posterButton: posterButton ?? { item, action, _ in
                MyPosterButton(
                    item: item,
                    type: type,
                    overlayOptions: .default,
                    unplayedIndicatorType: .none
                ) {
                    action()
                }
                .eraseToAnyView()
            },
            trailingContent: { EmptyView() },
            action: action
        )
    }

    func trailing(@ViewBuilder _ content: @escaping () -> any View) -> Self {
        copy(modifying: \.trailingContent, with: content)
    }

    func itemContentAspectRatio(_ aspectRatio: CGFloat) -> Self {
        copy(modifying: \.itemContentAspectRatio, with: aspectRatio)
    }
}
