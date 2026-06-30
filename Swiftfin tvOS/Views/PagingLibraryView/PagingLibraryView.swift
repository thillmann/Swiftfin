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

    @Default(.Customization.Library.rememberLayout)
    private var rememberLayout

    @Default(.Customization.Library.displayType)
    private var defaultDisplayType: LibraryDisplayType
    @Default(.Customization.Library.listColumnCount)
    private var defaultListColumnCount: Int
    @Default(.Customization.Library.posterType)
    private var defaultPosterType: PosterDisplayType
    @Default(.Customization.Indicators.showFavorited)
    private var showFavorited
    @Default(.Customization.Indicators.showProgress)
    private var showProgress
    @Default(.Customization.Indicators.showUnplayed)
    private var showUnplayed
    @Default(.Customization.Indicators.showPlayed)
    private var showPlayed

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

    @State
    private var pendingSeerrRequestItem: SeerrClient.MediaResult?

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
        case let element as UnifiedMediaResult:
            select(item: element)
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

    private func select(item: UnifiedMediaResult) {
        switch item {
        case let .jellyfin(baseItem):
            select(item: baseItem)
        case let .seerr(seerrItem):
            pendingSeerrRequestItem = seerrItem
        }
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

    private var posterOverlayOptions: PosterButtonOverlayOptions {
        PosterButtonOverlayOptions(
            showPlayed: showPlayed,
            showFavorited: showFavorited,
            showProgress: showProgress,
            showUnplayed: showUnplayed
        )
    }

    // MARK: Grid View

    @ViewBuilder
    private var contentView: some View {
        PosterVGrid(
            data: viewModel.items,
            layout: activeDisplayType,
            posterType: activePosterType,
            columnCount: activeColumnCount,
            overlayOptions: posterOverlayOptions,
            unplayedIndicatorType: showUnplayed,
            onNeedsNextPage: { item in
                viewModel.loadNextPageIfNeeded(currentItem: item)
            }
        ) { item in
            action(item)
        }
    }

    @ViewBuilder
    private var pagingErrorView: some View {
        if let pagingError = viewModel.pagingError {
            VStack(spacing: 16) {
                Text(pagingError.localizedDescription)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(L10n.retry, systemImage: "arrow.clockwise") {
                    viewModel.retryNextPage()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()

            switch viewModel.state {
            case .content:
                if viewModel.items.isEmpty {
                    ContentUnavailableView(L10n.noItems.localizedCapitalized, systemImage: "rectangle.on.rectangle.slash")
                } else {
                    contentView
                }
            case .initial, .refreshing:
                ProgressView()
            case let .error(error):
                ErrorView(error: error)
            }

            if viewModel.state == .content {
                VStack {
                    Spacer()

                    pagingErrorView
                }
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
                case let item as UnifiedMediaResult:
                    select(item: item)
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
        .fullScreenCover(item: $pendingSeerrRequestItem) { item in
            SeerrRequestView(item: item) {
                if let viewModel = viewModel as? SeerrRequestStateUpdating {
                    viewModel.markRequested(item)
                }
            }
        }
    }
}
