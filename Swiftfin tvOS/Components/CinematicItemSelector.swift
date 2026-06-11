//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import JellyfinAPI
import SwiftUI

// TODO: make new protocol for cinematic view image provider
// TODO: better name

struct CinematicItemSelector<Item: Poster>: View {

    @FocusState
    private var isSectionFocused

    @FocusState
    private var focusedItemID: Int?

    @StateObject
    private var viewModel: CinematicBackgroundView.Proxy = .init()

    private var topContent: (Item) -> any View
    private var itemContent: (Item) -> any View
    private var trailingContent: () -> any View
    private let action: (Item) -> Void

    let items: [Item]

    private var currentFocusedItem: Item? {
        guard isSectionFocused, let focusedItemID else { return nil }

        return items.first { $0.unwrappedIDHashOrZero == focusedItemID }
    }

    private var selectedItem: Item? {
        currentFocusedItem ?? viewModel.currentItem?._poster as? Item ?? items.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            if let selectedItem {
                topContent(selectedItem)
                    .eraseToAnyView()
                    .id(selectedItem.hashValue)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }

            PosterHStack(
                type: .landscape,
                items: items,
                posterButton: { item in
                    MyPosterButton(
                        item: item,
                        type: .landscape,
                        overlayOptions: .default,
                        unplayedIndicatorType: .none
                    ) {
                        action(item)
                    }
                    .focused($focusedItemID, equals: item.unwrappedIDHashOrZero)
                }
            )
        }
        .frame(height: UIScreen.main.bounds.height - 75, alignment: .bottomLeading)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            CinematicBackgroundView(
                viewModel: viewModel,
                initialItem: items.first
            )
            .frame(height: UIScreen.main.bounds.height)
            .maskLinearGradient {
                (location: 0.9, opacity: 1)
                (location: 1, opacity: 0)
            }
        }
        .onChange(of: focusedItemID) { _, newValue in
            guard let newValue,
                  let item = items.first(where: { $0.unwrappedIDHashOrZero == newValue })
            else {
                return
            }

            viewModel.select(item: item)
        }
        .focusSection()
        .focused($isSectionFocused)
    }
}

extension CinematicItemSelector {

    init(items: [Item], action: @escaping (Item) -> Void = { _ in }) {
        self.init(
            topContent: { _ in EmptyView() },
            itemContent: { _ in EmptyView() },
            trailingContent: { EmptyView() },
            action: action,
            items: items
        )
    }
}

extension CinematicItemSelector {

    func topContent(@ViewBuilder _ content: @escaping (Item) -> any View) -> Self {
        copy(modifying: \.topContent, with: content)
    }

    func content(@ViewBuilder _ content: @escaping (Item) -> any View) -> Self {
        copy(modifying: \.itemContent, with: content)
    }

    func trailingContent(@ViewBuilder _ content: @escaping () -> some View) -> Self {
        copy(modifying: \.trailingContent, with: content)
    }
}
