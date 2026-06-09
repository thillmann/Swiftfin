//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

// TODO: Figure out proper tab bar handling with the collection offset
// TODO: fix paging for next item focusing the tab

struct PagingLibraryView<Element: Poster & Identifiable>: View {

    private let pagingPrefetchRows = 8

    @Default(.Customization.Library.rememberLayout)
    private var rememberLayout

    @Default(.Customization.Library.displayType)
    private var defaultDisplayType: LibraryDisplayType
    @Default(.Customization.Library.listColumnCount)
    private var defaultListColumnCount: Int
    @Default(.Customization.Library.posterType)
    private var defaultPosterType: PosterDisplayType

    @Router
    private var router

    @StoredValue
    private var displayType: LibraryDisplayType
    @StoredValue
    private var listColumnCount: Int
    @StoredValue
    private var posterType: PosterDisplayType

    @StateObject
    private var viewModel: PagingLibraryViewModel<Element>

    init(viewModel: PagingLibraryViewModel<Element>) {

        self._displayType = StoredValue(.User.libraryDisplayType(parentID: viewModel.parent?.id))
        self._listColumnCount = StoredValue(.User.libraryListColumnCount(parentID: viewModel.parent?.id))
        self._posterType = StoredValue(.User.libraryPosterType(parentID: viewModel.parent?.id))

        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    // MARK: On Select

    private func action(_ element: Element) {
        switch element {
        case let element as BaseItemDto:
            select(item: element)
        case let element as BaseItemPerson:
            select(item: BaseItemDto(person: element))
        default:
            assertionFailure("Used an unexpected type within a `PagingLibaryView`?")
        }
    }

    private func select(item: BaseItemDto) {
        switch item.type {
        case .collectionFolder, .folder:
            let viewModel = ItemLibraryViewModel(parent: item, filters: .default)
            router.route(to: .library(viewModel: viewModel))
        default:
            router.route(to: .item(item: item))
        }
    }

    // MARK: Select Person

    private func select(person: BaseItemPerson) {
        let viewModel = ItemLibraryViewModel(parent: person)
        router.route(to: .library(viewModel: viewModel))
    }

    private var activeDisplayType: LibraryDisplayType {
        rememberLayout ? displayType : defaultDisplayType
    }

    private var activePosterType: PosterDisplayType {
        rememberLayout ? posterType : defaultPosterType
    }

    private var activeColumnCount: Int {
        switch (activePosterType, activeDisplayType) {
        case (.landscape, .grid):
            4
        case (.portrait, .grid), (.square, .grid):
            6
        case (_, .list):
            max(rememberLayout ? listColumnCount : defaultListColumnCount, 1)
        }
    }

    // MARK: Grid View

    @ViewBuilder
    private var gridView: some View {
        switch activeDisplayType {
        case .grid:
            LazyPosterVGrid(
                data: viewModel.lazyCollection,
                posterType: activePosterType,
                columnCount: activeColumnCount
            ) { item in
                action(item)
            }
        case .list:
            VirtualizedPosterGrid(
                items: viewModel.itemSnapshot,
                posterType: activePosterType,
                displayType: activeDisplayType,
                columnCount: activeColumnCount,
                spacing: 50,
                pagingPrefetchRows: pagingPrefetchRows
            ) { item in
                action(item)
            } onNearEnd: {
                loadNextPageIfNeeded()
            }
        }
    }

    private func loadNextPageIfNeeded() {
        guard !viewModel.backgroundStates.contains(.gettingNextPage) else { return }

        viewModel.send(.getNextPage)
    }

    // MARK: Content View

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .content:
            if viewModel.itemSnapshot.isEmpty {
                ContentUnavailableView(L10n.noItems.localizedCapitalized, systemImage: "rectangle.on.rectangle.slash")
            } else {
                gridView
            }
        case .initial, .refreshing:
            ProgressView()
        default:
            AssertionFailureView("Expected view for unexpected state")
        }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()

            switch viewModel.state {
            case .content, .initial, .refreshing:
                contentView
            case let .error(error):
                ErrorView(error: error)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.linear(duration: 0.1), value: viewModel.state)
        .navigationTitle(viewModel.parent?.displayTitle ?? "")
        .ignoresSafeArea(.all, edges: .vertical)
        .letterPickerBar(filterViewModel: viewModel.filterViewModel)
        .refreshable {
            viewModel.send(.refresh)
        }
        .onChange(of: viewModel.filterViewModel?.currentFilters) { _, newValue in
            guard let newValue, let id = viewModel.parent?.id else { return }

            if Defaults[.Customization.Library.rememberSort] {
                let newStoredFilters = StoredValues[.User.libraryFilters(parentID: id)]
                    .mutating(\.sortBy, with: newValue.sortBy)
                    .mutating(\.sortOrder, with: newValue.sortOrder)

                StoredValues[.User.libraryFilters(parentID: id)] = newStoredFilters
            }
        }
        .onReceive(viewModel.events) { event in
            switch event {
            case let .gotRandomItem(item):
                switch item {
                case let item as BaseItemDto:
                    select(item: item)
                case let item as BaseItemPerson:
                    select(item: BaseItemDto(person: item))
                default:
                    assertionFailure("Used an unexpected type within a `PagingLibaryView`?")
                }
            }
        }
        .onFirstAppear {
            if viewModel.state == .initial {
                viewModel.send(.refresh)
            }
        }
    }
}
