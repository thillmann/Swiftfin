//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftUI

struct GenreLibraryView: View {

    let genre: MediaGenre

    @StateObject
    private var viewModel: GenreLibraryViewModel

    @Router
    private var router

    @State
    private var pendingRequestItem: SeerrClient.MediaResult?

    @FocusState
    private var focusedItemID: String?

    private var hasNoItems: Bool {
        viewModel.inLibraryItems.isEmpty && viewModel.availableItems.isEmpty
    }

    private let columnCount = 6
    private let gridSpacing: CGFloat = 40
    private let horizontalPadding: CGFloat = 80
    private let posterAspectRatio: CGFloat = 2 / 3

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: gridSpacing),
            count: columnCount
        )
    }

    init(
        genre: MediaGenre,
        itemTypes: [BaseItemKind] = [.movie, .series]
    ) {
        self.genre = genre
        self._viewModel = StateObject(wrappedValue: GenreLibraryViewModel(
            genre: genre,
            itemTypes: itemTypes
        ))
    }

    var body: some View {
        ZStack {
            if let error = viewModel.error, hasNoItems {
                ErrorView(error: error)
            } else if viewModel.isLoading, hasNoItems {
                ProgressView()
            } else if hasNoItems {
                ContentUnavailableView(L10n.noItems, systemImage: "square.grid.2x2")
            } else {
                contentView
            }
        }
        .ignoresSafeArea()
        .navigationTitle(genre.displayTitle)
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .fullScreenCover(item: $pendingRequestItem) { item in
            SeerrRequestView(item: item) {
                viewModel.markRequested(item)
            }
        }
    }

    private var contentView: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    mediaSection(
                        title: "In Library",
                        items: viewModel.inLibraryItems,
                        containerWidth: proxy.size.width,
                        showsLoadingFooter: false,
                        onNeedsNextPage: { _ in }
                    )

                    mediaSection(
                        title: "Available",
                        items: viewModel.availableItems,
                        containerWidth: proxy.size.width,
                        showsLoadingFooter: viewModel.isLoadingAvailableItems,
                        onNeedsNextPage: viewModel.loadNextSeerrPageIfNeeded(currentItem:)
                    )
                }
                .padding(.top, 120)
                .padding(.bottom, 80)
                .padding(.horizontal, horizontalPadding)
            }
        }
    }

    @ViewBuilder
    private func mediaSection(
        title: String,
        items: [UnifiedMediaResult],
        containerWidth: CGFloat,
        showsLoadingFooter: Bool,
        onNeedsNextPage: @escaping (UnifiedMediaResult) -> Void
    ) -> some View {
        if items.isNotEmpty || showsLoadingFooter {
            Section {
                ForEach(items) { item in
                    PosterButton(item: item, type: .portrait) {
                        select(item)
                    } overlay: {
                        UnifiedMediaResultPosterOverlay(item: item)
                    }
                    .frame(
                        width: itemWidth(containerWidth: containerWidth),
                        height: itemHeight(containerWidth: containerWidth)
                    )
                    .focused($focusedItemID, equals: item.id)
                    .onChange(of: focusedItemID) { _, newValue in
                        guard newValue == item.id else { return }
                        onNeedsNextPage(item)
                    }
                }
            } header: {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .accessibility(addTraits: [.isHeader])
                    .frame(maxWidth: .infinity, alignment: .leading)
            } footer: {
                if showsLoadingFooter {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                }
            }
        }
    }

    private func itemWidth(containerWidth: CGFloat) -> CGFloat {
        let availableWidth = containerWidth - horizontalPadding * 2 - gridSpacing * CGFloat(columnCount - 1)
        return max(availableWidth / CGFloat(columnCount), 1)
    }

    private func itemHeight(containerWidth: CGFloat) -> CGFloat {
        itemWidth(containerWidth: containerWidth) / posterAspectRatio
    }

    private func select(_ item: UnifiedMediaResult) {
        switch item {
        case let .jellyfin(baseItem):
            router.route(to: .item(item: baseItem))
        case let .seerr(seerrItem):
            pendingRequestItem = seerrItem
        }
    }
}

@MainActor
private final class GenreLibraryViewModel: ViewModel {

    @Published
    private(set) var inLibraryItems: [UnifiedMediaResult] = []

    @Published
    private(set) var availableItems: [UnifiedMediaResult] = []

    @Published
    private(set) var error: ErrorMessage?

    @Published
    private(set) var isLoading = false

    @Published
    private(set) var isLoadingAvailableItems = false

    private let genre: MediaGenre
    private let itemTypes: [BaseItemKind]
    private let pageSize: Int

    private var didLoadInitialPage = false
    private var pagingGeneration = 0

    private lazy var mediaSource = GenreMediaSource(
        genre: genre,
        itemTypes: itemTypes,
        pageSize: pageSize,
        viewModel: self
    )

    init(
        genre: MediaGenre,
        itemTypes: [BaseItemKind] = [.movie, .series],
        pageSize: Int = 20
    ) {
        self.genre = genre
        self.itemTypes = itemTypes
        self.pageSize = pageSize

        super.init()
    }

    func loadIfNeeded() async {
        guard !didLoadInitialPage else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        resetPaging()
        defer {
            isLoading = false
            didLoadInitialPage = true
        }

        do {
            inLibraryItems = try await mediaSource.loadAllInLibraryItems()
        } catch {
            guard isCurrentGeneration(pagingGeneration) else { return }
            self.error = ErrorMessage(error.localizedDescription)
            return
        }

        await loadNextSeerrPage()
    }

    func loadNextSeerrPageIfNeeded(currentItem: UnifiedMediaResult) {
        guard shouldLoadNextPage(currentItem: currentItem, in: availableItems) else { return }

        Task {
            await loadNextSeerrPage()
        }
    }

    func markRequested(_ requestedItem: SeerrClient.MediaResult) {
        availableItems = availableItems.map { item in
            guard case let .seerr(seerrItem) = item else { return item }
            guard seerrItem.id == requestedItem.id, seerrItem.mediaType == requestedItem.mediaType else { return item }
            return .seerr(seerrItem.updatingStatus(.pending))
        }
    }

    private func resetPaging() {
        pagingGeneration += 1
        inLibraryItems = []
        availableItems = []
        isLoadingAvailableItems = false
        mediaSource.reset()
    }

    private func shouldLoadNextPage(
        currentItem: UnifiedMediaResult,
        in items: [UnifiedMediaResult]
    ) -> Bool {
        guard let index = items.firstIndex(of: currentItem) else { return false }
        let threshold = max(6, pageSize / 2)

        return index >= items.count - threshold
    }

    private func loadNextSeerrPage() async {
        guard mediaSource.hasNextAvailablePage, !isLoadingAvailableItems else { return }

        let generation = pagingGeneration
        isLoadingAvailableItems = true
        defer {
            if isCurrentGeneration(generation) {
                isLoadingAvailableItems = false
            }
        }

        let appendedItems = await mediaSource.loadNextAvailablePage()
        guard isCurrentGeneration(generation) else { return }

        appendAvailableItems(appendedItems)
    }

    private func isCurrentGeneration(_ generation: Int) -> Bool {
        pagingGeneration == generation
    }

    private func appendAvailableItems(_ items: [UnifiedMediaResult]) {
        var knownIDs = Set(availableItems.map(\.id))
        let newItems = items.filter { knownIDs.insert($0.id).inserted }

        availableItems += newItems
    }
}
