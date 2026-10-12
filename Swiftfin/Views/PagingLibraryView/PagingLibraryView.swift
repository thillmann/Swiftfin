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

// TODO: need to think about better design for views that may not support current library display type
//       - ex: channels/albums when in portrait/landscape
//       - just have the supported view embedded in a container view?
// TODO: when there are no filters sometimes navigation bar will be clear until popped back to

/*
 Note: Currently, it is a conscious decision to not have grid posters have subtitle content.
       This is due to episodes, which have their `S_E_` subtitles, and these can be alongside
       other items that don't have a subtitle which requires the entire library to implement
       subtitle content but that doesn't look appealing. Until a solution arrives grid posters
       will not have subtitle content.
       There should be a solution since there are contexts where subtitles are desirable and/or
       we can have subtitle content for other items.

 */

struct PlatformPagingLibraryView<Element: PlatformPoster>: View {

    @Default(.Customization.Library.rememberLayout)
    private var rememberLayout

    @Default(.Customization.Library.displayType)
    private var defaultDisplayType: LibraryDisplayType
    @Default(.Customization.Library.listColumnCount)
    private var defaultListColumnCount: Int
    @Default(.Customization.Library.posterType)
    private var defaultPosterType: PosterDisplayType

    @Namespace
    private var namespace

    @Router
    private var router
    @TabItemSelected
    private var tabItemSelected

    @StoredValue
    private var displayType: LibraryDisplayType
    @StoredValue
    private var listColumnCount: Int
    @StoredValue
    private var posterType: PosterDisplayType

    @StateObject
    private var viewModel: PlatformPagingLibraryViewModel<Element>

    @State
    private var pendingSeerrRequestItem: SeerrClient.MediaResult?

    private let fallbackNavigationTitle: String?
    private let showsGenreFilter: Bool
    private let scrollTopID = "library-scroll-top"

    // MARK: init

    init(
        viewModel: PlatformPagingLibraryViewModel<Element>,
        navigationTitle: String? = nil,
        showsGenreFilter: Bool = false
    ) {

        self._displayType = StoredValue(.User.libraryDisplayType(parentID: viewModel.parent?.id))
        self._listColumnCount = StoredValue(.User.libraryListColumnCount(parentID: viewModel.parent?.id))
        self._posterType = StoredValue(.User.libraryPosterType(parentID: viewModel.parent?.id))

        self._viewModel = StateObject(wrappedValue: viewModel)
        self.fallbackNavigationTitle = navigationTitle
        self.showsGenreFilter = showsGenreFilter
    }

    // MARK: action

    private func action(_ element: Element, in namespace: Namespace.ID) {
        switch element {
        case let element as BaseItemDto:
            select(item: element, in: namespace)
        case let element as BaseItemPerson:
            select(item: BaseItemDto(person: element), in: namespace)
        case let element as UnifiedMediaResult:
            select(item: element, in: namespace)
        default:
            assertionFailure("Used an unexpected type within a `PlatformPagingLibraryView`?")
        }
    }

    private func select(item: BaseItemDto, in namespace: Namespace.ID) {
        switch item.type {
        case .collectionFolder, .folder:
            let viewModel = ItemLibraryViewModel(parent: item, filters: .default)
            router.route(to: .library(viewModel: viewModel), in: namespace)
        default:
            router.route(to: .item(item: item), in: namespace)
        }
    }

    private func select(item: UnifiedMediaResult, in namespace: Namespace.ID) {
        switch item {
        case let .jellyfin(baseItem):
            select(item: baseItem, in: namespace)
        case let .seerr(seerrItem):
            pendingSeerrRequestItem = seerrItem
        }
    }

    // MARK: item view

    // Note: if parent is a folders then other items will have labels,
    //       so an empty content view is necessary

    @ViewBuilder
    private func gridItemView(item: Element, posterType: PosterDisplayType) -> some View {
        PlatformPosterButton(
            item: item,
            type: posterType
        ) { namespace in
            action(item, in: namespace)
        } label: {
            if item.showTitle {
                PosterButtonTitleContentView(title: item.displayTitle)
                    .lineLimit(1, reservesSpace: true)
            } else if viewModel.parent?.libraryType == .folder {
                PosterButtonTitleContentView(title: item.displayTitle)
                    .lineLimit(1, reservesSpace: true)
                    .hidden()
            }
        }
    }

    @ViewBuilder
    private func listItemView(item: Element, posterType: PosterDisplayType) -> some View {
        LibraryRow(
            item: item,
            posterType: posterType
        ) { namespace in
            action(item, in: namespace)
        }
    }

    private var activeDisplayType: LibraryDisplayType {
        rememberLayout ? displayType : defaultDisplayType
    }

    private var isRootLibrary: Bool {
        viewModel.parent == nil
    }

    private var navigationTitle: String {
        viewModel.parent?.displayTitle ?? fallbackNavigationTitle ?? ""
    }

    private var activePosterType: PosterDisplayType {
        rememberLayout ? posterType : defaultPosterType
    }

    private var activeListColumnCount: Int {
        if UIDevice.isPhone {
            1
        } else {
            max(rememberLayout ? listColumnCount : defaultListColumnCount, 1)
        }
    }

    private var gridSpacing: CGFloat {
        activeDisplayType == .grid ? EdgeInsets.edgePadding / 2 : 0
    }

    private var horizontalPadding: CGFloat {
        activeDisplayType == .grid ? EdgeInsets.edgePadding : 0
    }

    private var topPadding: CGFloat {
        isRootLibrary ? 32 : 0
    }

    private var gridRenderID: AnyHashable {
        let libraryType = viewModel.parent?.libraryType?.rawValue ?? "none"
        return AnyHashable(
            "\(activeDisplayType.rawValue)-\(activePosterType.rawValue)-\(libraryType)"
        )
    }

    private var posterAspectRatio: CGFloat? {
        guard activeDisplayType == .grid else { return nil }

        return switch activePosterType {
        case .landscape:
            1.77
        case .portrait:
            2 / 3
        case .square:
            1
        }
    }

    private var columns: [GridItem] {
        switch (activeDisplayType, activePosterType) {
        case (.grid, .landscape) where UIDevice.isPhone:
            Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 2)
        case (.grid, .portrait), (.grid, .square) where UIDevice.isPhone:
            Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 3)
        case (.grid, .landscape):
            [GridItem(.adaptive(minimum: 200), spacing: gridSpacing)]
        case (.grid, .portrait), (.grid, .square):
            [GridItem(.adaptive(minimum: 150), spacing: gridSpacing)]
        case (.list, _):
            Array(repeating: GridItem(.flexible(), spacing: 0), count: activeListColumnCount)
        }
    }

    private func genreFilterButton(filterViewModel: FilterViewModel) -> some View {
        LibraryGenreFilterButton(viewModel: filterViewModel)
    }

    @ViewBuilder
    private func styledGenreFilterButton(filterViewModel: FilterViewModel) -> some View {
        if #available(iOS 26.0, *) {
            genreFilterButton(filterViewModel: filterViewModel)
                .buttonStyle(.glass)
        } else {
            genreFilterButton(filterViewModel: filterViewModel)
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var libraryHeader: some View {
        if isRootLibrary, navigationTitle.isNotEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(navigationTitle)
                    .font(.largeTitle.weight(.bold))

                Spacer()

                if showsGenreFilter, let filterViewModel = viewModel.filterViewModel {
                    styledGenreFilterButton(filterViewModel: filterViewModel)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, UIDevice.isPad ? 80 : 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var emptyLibraryView: some View {
        if isRootLibrary {
            VStack(spacing: 0) {
                libraryHeader

                ContentUnavailableView(
                    L10n.noItems.localizedCapitalized,
                    systemImage: "rectangle.on.rectangle.slash"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ContentUnavailableView(L10n.noItems.localizedCapitalized, systemImage: "rectangle.on.rectangle.slash")
        }
    }

    @ViewBuilder
    private var elementsView: some View {
        ScrollViewReader { proxy in
            PosterVGrid(
                data: viewModel.items,
                columns: columns,
                spacing: gridSpacing,
                horizontalPadding: horizontalPadding,
                topPadding: topPadding,
                posterAspectRatio: posterAspectRatio,
                showsHeader: isRootLibrary,
                onNeedsNextPage: { viewModel.loadNextPageIfNeeded(currentItem: $0) },
                renderID: gridRenderID,
                header: { libraryHeader.id(scrollTopID) }
            ) { item in
                switch activeDisplayType {
                case .grid:
                    gridItemView(item: item, posterType: activePosterType)
                case .list:
                    listItemView(item: item, posterType: activePosterType)
                }
            }
            .onReceive(tabItemSelected) { event in
                guard isRootLibrary, event.isRepeat, event.isRoot else { return }

                withAnimation {
                    proxy.scrollTo(scrollTopID, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .content:
            if viewModel.items.isEmpty {
                emptyLibraryView
            } else {
                elementsView
            }
        case .initial, .refreshing:
            ProgressView()
        default:
            AssertionFailureView("Expected view for unexpected state")
        }
    }

    // MARK: body

    // TODO: becoming too large for typechecker during development, should break up somehow

    var body: some View {
        ZStack {
            Color.clear

            switch viewModel.state {
            case .content, .initial, .refreshing:
                contentView
            case let .error(error):
                ErrorView(error: error)
            }
        }
        .animation(.linear(duration: 0.1), value: viewModel.state)
        .letterPickerBar(filterViewModel: viewModel.filterViewModel)
        .if(isRootLibrary) { view in
            view
                .ignoresSafeArea(.container, edges: .top)
                .toolbar(.hidden, for: .navigationBar)
        }
        .if(!isRootLibrary) { view in
            view
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
        }
        .refreshable {
            viewModel.send(.refresh)
        }
        .onChange(of: viewModel.filterViewModel?.currentFilters) { newValue in
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
                    select(item: item, in: namespace)
                case let item as BaseItemPerson:
                    select(item: BaseItemDto(person: item), in: namespace)
                case let item as UnifiedMediaResult:
                    select(item: item, in: namespace)
                default:
                    assertionFailure("Used an unexpected type within a `PlatformPagingLibraryView`?")
                }
            }
        }
        .onFirstAppear {
            if viewModel.state == .initial {
                viewModel.send(.refresh)
            }
        }
        .posterOverlay(for: UnifiedMediaResult.self) { item in
            UnifiedMediaResultPosterOverlay(item: item)
        }
        .sheet(item: $pendingSeerrRequestItem) { item in
            SeerrRequestView(item: item) {
                if let viewModel = viewModel as? SeerrRequestStateUpdating {
                    viewModel.markRequested(item)
                }
            }
        }
    }
}

private struct LibraryGenreFilterButton: View {

    @ObservedObject
    var viewModel: FilterViewModel

    @Router
    private var router

    private var activeFilterCount: Int {
        viewModel.currentFilters.genres.count
    }

    var body: some View {
        Button {
            router.route(to: .filter(type: .genres, viewModel: viewModel))
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.primary)
                .padding(8)
        }
        .buttonBorderShape(.circle)
        .overlay(alignment: .topTrailing) {
            if activeFilterCount > 0 {
                Text(activeFilterCount, format: .number)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: .capsule)
                    .offset(y: -6)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(L10n.genres)
        .accessibilityValue(activeFilterCount.formatted())
    }
}
