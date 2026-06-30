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

    let genre: ItemGenre

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

    init(genre: ItemGenre) {
        self.genre = genre
        self._viewModel = StateObject(wrappedValue: GenreLibraryViewModel(genre: genre))
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
                        onNeedsNextPage: viewModel.loadNextJellyfinPageIfNeeded(currentItem:)
                    )

                    mediaSection(
                        title: "Available",
                        items: viewModel.availableItems,
                        containerWidth: proxy.size.width,
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
        onNeedsNextPage: @escaping (UnifiedMediaResult) -> Void
    ) -> some View {
        if items.isNotEmpty {
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

    private let genre: ItemGenre
    private let jellyfinViewModel: ItemLibraryViewModel
    private let pageSize: Int
    private let maxSeerrPagesPerLoad = 3

    private var didLoadInitialPage = false
    private var jellyfinPage = -1
    private var hasNextJellyfinPage = true
    private var isLoadingNextJellyfinPage = false
    private var nextSeerrPage = 1
    private var hasNextSeerrPage = true
    private var isLoadingNextSeerrPage = false
    private var librarySignatures = Set<String>()
    private var availableIDs = Set<String>()
    private var pagingGeneration = 0

    init(
        genre: ItemGenre,
        itemTypes: [BaseItemKind] = [.movie, .series],
        pageSize: Int = 20
    ) {
        let parent = TitledLibraryParent(
            displayTitle: genre.displayTitle,
            id: genre.id ?? genre.value
        )
        let filters = ItemFilterCollection(
            genres: [genre],
            itemTypes: itemTypes
        )

        self.genre = genre
        self.pageSize = pageSize
        self.jellyfinViewModel = ItemLibraryViewModel(
            parent: parent,
            filters: filters,
            pageSize: pageSize
        )

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

        await loadNextJellyfinPage()
        await loadNextSeerrPage()
    }

    func loadNextJellyfinPageIfNeeded(currentItem: UnifiedMediaResult) {
        guard shouldLoadNextPage(currentItem: currentItem, in: inLibraryItems) else { return }

        Task {
            await loadNextJellyfinPage()
        }
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
        jellyfinPage = -1
        hasNextJellyfinPage = true
        isLoadingNextJellyfinPage = false
        nextSeerrPage = 1
        hasNextSeerrPage = true
        isLoadingNextSeerrPage = false
        librarySignatures = []
        availableIDs = []
    }

    private func shouldLoadNextPage(
        currentItem: UnifiedMediaResult,
        in items: [UnifiedMediaResult]
    ) -> Bool {
        guard let index = items.firstIndex(of: currentItem) else { return false }
        let threshold = max(6, pageSize / 2)

        return index >= items.count - threshold
    }

    private func loadNextJellyfinPage() async {
        guard hasNextJellyfinPage, !isLoadingNextJellyfinPage else { return }

        let generation = pagingGeneration
        isLoadingNextJellyfinPage = true
        defer {
            if isCurrentGeneration(generation) {
                isLoadingNextJellyfinPage = false
            }
        }

        do {
            let page = jellyfinPage + 1
            let fetchedItems = try await jellyfinViewModel.get(page: page)

            guard isCurrentGeneration(generation) else { return }

            jellyfinPage = page
            hasNextJellyfinPage = fetchedItems.count >= pageSize

            for item in fetchedItems {
                librarySignatures.insert(SeerrLibraryMatcher.mediaSignature(for: item))
            }

            appendInLibraryItems(fetchedItems.map(UnifiedMediaResult.jellyfin))
            removeAvailableItemsNowInLibrary()
        } catch {
            guard isCurrentGeneration(generation) else { return }
            self.error = ErrorMessage(error.localizedDescription)
        }
    }

    private func loadNextSeerrPage() async {
        guard hasNextSeerrPage, !isLoadingNextSeerrPage else { return }
        guard SeerrIntegration.isAvailable else {
            hasNextSeerrPage = false
            return
        }
        guard SeerrGenreMapper.mapping(for: genre) != nil else {
            hasNextSeerrPage = false
            return
        }

        let generation = pagingGeneration
        isLoadingNextSeerrPage = true
        defer {
            if isCurrentGeneration(generation) {
                isLoadingNextSeerrPage = false
            }
        }

        var appendedItems: [UnifiedMediaResult] = []

        for _ in 0 ..< maxSeerrPagesPerLoad {
            let page = nextSeerrPage
            let seerrPage = await getSeerrItems(page: page)

            guard isCurrentGeneration(generation) else { return }

            nextSeerrPage += 1
            hasNextSeerrPage = seerrPage.hasNextPage

            guard seerrPage.items.isNotEmpty else { break }

            let availableSeerrItems = await availableSeerrItems(from: seerrPage.items)

            guard isCurrentGeneration(generation) else { return }

            appendedItems.append(contentsOf: availableSeerrItems.map(UnifiedMediaResult.seerr))

            if appendedItems.count >= pageSize || !hasNextSeerrPage {
                break
            }
        }

        appendAvailableItems(appendedItems)
    }

    private func isCurrentGeneration(_ generation: Int) -> Bool {
        pagingGeneration == generation
    }

    private func appendInLibraryItems(_ items: [UnifiedMediaResult]) {
        var knownIDs = Set(inLibraryItems.map(\.id))
        let newItems = items.filter { knownIDs.insert($0.id).inserted }

        inLibraryItems.append(contentsOf: newItems)
    }

    private func appendAvailableItems(_ items: [UnifiedMediaResult]) {
        var newItems: [UnifiedMediaResult] = []

        for item in items {
            guard case let .seerr(seerrItem) = item else { continue }
            let key = SeerrLibraryMatcher.key(for: seerrItem)
            guard availableIDs.insert(key).inserted else { continue }

            newItems.append(item)
        }

        availableItems += newItems
    }

    private func removeAvailableItemsNowInLibrary() {
        availableItems.removeAll { item in
            librarySignatures.contains(mediaSignature(for: item))
        }
        availableIDs = Set(availableItems.compactMap { item in
            guard case let .seerr(seerrItem) = item else { return nil }
            return SeerrLibraryMatcher.key(for: seerrItem)
        })
    }

    private func availableSeerrItems(from items: [SeerrClient.MediaResult]) async -> [SeerrClient.MediaResult] {
        var results: [SeerrClient.MediaResult] = []

        for item in items {
            let signature = SeerrLibraryMatcher.mediaSignature(for: item)
            guard !librarySignatures.contains(signature) else { continue }
            guard availableIDs.contains(SeerrLibraryMatcher.key(for: item)) == false else { continue }
            guard await libraryMatch(for: item) == nil else {
                librarySignatures.insert(signature)
                continue
            }

            results.append(item)
        }

        return results
    }

    private func getSeerrItems(page: Int) async -> (items: [SeerrClient.MediaResult], hasNextPage: Bool) {
        guard let mapping = SeerrGenreMapper.mapping(for: genre) else { return ([], false) }

        var results: [SeerrClient.MediaResult] = []
        var hasNextPage = false

        if let movieGenreID = mapping.movieGenreID {
            switch await SeerrClient.discoverMovies(page: page, language: "en", genreID: movieGenreID) {
            case let .success(response):
                results.append(contentsOf: response.results)
                hasNextPage = hasNextPage || page < (response.totalPages ?? page)
            case .failure:
                break
            }
        }

        if let tvGenreID = mapping.tvGenreID {
            switch await SeerrClient.discoverTV(page: page, language: "en", genreID: tvGenreID) {
            case let .success(response):
                results.append(contentsOf: response.results)
                hasNextPage = hasNextPage || page < (response.totalPages ?? page)
            case .failure:
                break
            }
        }

        return (
            deduplicatedSeerrItems(results.filter { item in
                item.originalLanguage == "en" && SeerrLibraryMatcher.jellyfinItemType(for: item) != nil
            }),
            hasNextPage
        )
    }

    private func libraryMatch(for result: SeerrClient.MediaResult) async -> BaseItemDto? {
        do {
            return try await SeerrLibraryMatcher.libraryMatch(for: result, using: self)
        } catch {
            return nil
        }
    }

    private func deduplicatedSeerrItems(_ results: [SeerrClient.MediaResult]) -> [SeerrClient.MediaResult] {
        var seenIDs = Set<String>()

        return results.filter { item in
            seenIDs.insert(SeerrLibraryMatcher.key(for: item)).inserted
        }
    }

    private func mediaSignature(for result: UnifiedMediaResult) -> String {
        switch result {
        case let .jellyfin(item):
            SeerrLibraryMatcher.mediaSignature(for: item)
        case let .seerr(item):
            SeerrLibraryMatcher.mediaSignature(for: item)
        }
    }
}
