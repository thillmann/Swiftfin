//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
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
    private var label: (Element) -> any View
    private var posterButton: PosterButtonBuilder
    private var trailingContent: () -> any View
    private let action: (Element) -> Void

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

            CollectionHStack(
                uniqueElements: data,
                columns: type == .landscape ? 4 : 6
            ) { item in
                posterButton(item, {
                    action(item)
                }, {
                    label(item).eraseToAnyView()
                })
            }
            .clipsToBounds(false)
            .dataPrefix(20)
            .insets(horizontal: EdgeInsets.edgePadding, vertical: 20)
            .itemSpacing(EdgeInsets.edgePadding - 40)
            .scrollBehavior(.continuousLeadingEdge)
        }
        .focusSection()
    }
}

extension PosterHStack {

    init(
        title: String? = nil,
        type: PosterDisplayType,
        items: Data,
        action: @escaping (Element) -> Void,
        @ViewBuilder label: @escaping (Element) -> any View = { PosterButton<Element>.TitleSubtitleContentView(item: $0) },
        posterButton: PosterButtonBuilder? = nil
    ) {
        self.init(
            data: items,
            title: title,
            type: type,
            label: label,
            posterButton: posterButton ?? { item, action, label in
                PosterButton(
                    item: item,
                    type: type
                ) {
                    action()
                } label: {
                    label()
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
}
