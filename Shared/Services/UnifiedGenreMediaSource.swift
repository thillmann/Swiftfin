//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

@MainActor
final class UnifiedGenreMediaSource {

    private let genre: UnifiedGenre
    private let itemTypes: [BaseItemKind]
    private let pageSize: Int
    private let maxSeerrPagesPerLoad: Int
    private let viewModel: ViewModel

    private var nextSeerrPage = 1
    private(set) var hasNextAvailablePage = true
    private var isLoadingNextAvailablePage = false
    private var librarySignatures = Set<String>()
    private var availableIDs = Set<String>()

    init(
        genre: UnifiedGenre,
        itemTypes: [BaseItemKind] = [.movie, .series],
        pageSize: Int = 20,
        maxSeerrPagesPerLoad: Int = 3,
        viewModel: ViewModel
    ) {
        self.genre = genre
        self.itemTypes = itemTypes
        self.pageSize = pageSize
        self.maxSeerrPagesPerLoad = maxSeerrPagesPerLoad
        self.viewModel = viewModel
    }

    func reset() {
        nextSeerrPage = 1
        hasNextAvailablePage = true
        isLoadingNextAvailablePage = false
        librarySignatures = []
        availableIDs = []
    }

    func loadAllInLibraryItems() async throws -> [UnifiedMediaResult] {
        let fetchedItems = try await fetchAllJellyfinItems()
        librarySignatures = Set(fetchedItems.map { item in
            SeerrLibraryMatcher.mediaSignature(for: item)
        })

        return deduplicatedJellyfinItems(fetchedItems).map(UnifiedMediaResult.jellyfin)
    }

    func loadNextAvailablePage() async -> [UnifiedMediaResult] {
        guard hasNextAvailablePage, !isLoadingNextAvailablePage else { return [] }
        guard SeerrIntegration.isAvailable else {
            hasNextAvailablePage = false
            return []
        }
        guard genre.seerrMovieGenreIDs.isNotEmpty || genre.seerrTVGenreIDs.isNotEmpty else {
            hasNextAvailablePage = false
            return []
        }

        isLoadingNextAvailablePage = true
        defer {
            isLoadingNextAvailablePage = false
        }

        var appendedItems: [SeerrClient.MediaResult] = []

        for _ in 0 ..< maxSeerrPagesPerLoad {
            let page = nextSeerrPage
            let seerrPage = await getSeerrItems(page: page)

            nextSeerrPage += 1
            hasNextAvailablePage = seerrPage.hasNextPage

            guard seerrPage.items.isNotEmpty else { break }

            let availableSeerrItems = await availableSeerrItems(from: seerrPage.items)
            appendedItems.append(contentsOf: availableSeerrItems)

            if appendedItems.count >= pageSize || !hasNextAvailablePage {
                break
            }
        }

        return appendedItems.map(UnifiedMediaResult.seerr)
    }

    private func fetchAllJellyfinItems() async throws -> [BaseItemDto] {
        var fetchedItems: [BaseItemDto] = []

        for jellyfinGenre in genre.jellyfinGenres {
            let viewModel = jellyfinViewModel(genres: [jellyfinGenre], pageSize: pageSize)
            var page = 0

            while true {
                try Task.checkCancellation()

                let items = try await viewModel.get(page: page)
                fetchedItems.append(contentsOf: items)

                guard items.count >= pageSize else { break }
                page += 1
            }
        }

        return fetchedItems
    }

    private func jellyfinViewModel(
        genres: [ItemGenre],
        sortBy: [ItemSortBy] = [ItemSortBy.sortName],
        pageSize: Int
    ) -> ItemLibraryViewModel {
        let parent = TitledLibraryParent(
            displayTitle: genre.displayTitle,
            id: nil
        )
        let filters = ItemFilterCollection(
            genres: genres,
            itemTypes: itemTypes,
            sortBy: sortBy
        )

        return ItemLibraryViewModel(
            parent: parent,
            filters: filters,
            pageSize: pageSize
        )
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
            availableIDs.insert(SeerrLibraryMatcher.key(for: item))
        }

        return results
    }

    private func getSeerrItems(page: Int) async -> (items: [SeerrClient.MediaResult], hasNextPage: Bool) {
        var results: [SeerrClient.MediaResult] = []
        var hasNextPage = false

        for movieGenreID in genre.seerrMovieGenreIDs {
            switch await SeerrClient.discoverMovies(page: page, language: "en", genreID: movieGenreID) {
            case let .success(response):
                results.append(contentsOf: response.results)
                hasNextPage = hasNextPage || page < (response.totalPages ?? page)
            case .failure:
                break
            }
        }

        for tvGenreID in genre.seerrTVGenreIDs {
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
            return try await SeerrLibraryMatcher.libraryMatch(for: result, using: viewModel)
        } catch {
            return nil
        }
    }

    private func deduplicatedJellyfinItems(_ results: [BaseItemDto]) -> [BaseItemDto] {
        var seenIDs = Set<String>()

        return results.filter { item in
            let key = item.id ?? SeerrLibraryMatcher.mediaSignature(for: item)
            return seenIDs.insert(key).inserted
        }
    }

    private func deduplicatedSeerrItems(_ results: [SeerrClient.MediaResult]) -> [SeerrClient.MediaResult] {
        var seenIDs = Set<String>()

        return results.filter { item in
            seenIDs.insert(SeerrLibraryMatcher.key(for: item)).inserted
        }
    }
}
