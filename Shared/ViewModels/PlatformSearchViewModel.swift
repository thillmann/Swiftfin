//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI
import OrderedCollections

@MainActor
@Stateful
final class PlatformSearchViewModel: ViewModel {
    @CasePathable
    enum Action {
        case getSuggestions
        case search(query: String)
        case actuallySearch(query: String)

        var transition: Transition {
            switch self {
            case .getSuggestions:
                .none
            case .search:
                .none
            case .actuallySearch:
                .to(.searching, then: .initial)
                    .onRepeat(.cancel)
            }
        }
    }

    enum State {
        case error
        case initial
        case searching
    }

    @Published
    private(set) var items: [BaseItemKind: [BaseItemDto]] = [:]
    @Published
    private(set) var seerItems: [SeerrClient.MediaResult] = []
    @Published
    private(set) var unifiedItems: [BaseItemKind: [UnifiedMediaResult]] = [:]
    @Published
    private(set) var suggestions: [BaseItemDto] = []

    private var searchQuery: CurrentValueSubject<String, Never> = .init("")

    let filterViewModel: FilterViewModel

    var hasNoResults: Bool {
        unifiedItems.values.allSatisfy(\.isEmpty)
    }

    var canSearch: Bool {
        searchQuery.value.isNotEmpty || filterViewModel.currentFilters.hasQueryableFilters
    }

    // MARK: init

    @MainActor
    init(filterViewModel: FilterViewModel) {
        self.filterViewModel = filterViewModel
        super.init()

        searchQuery
            .combineLatest(filterViewModel.$currentFilters)
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] query, _ in
                guard let self else { return }

                searchIfNeeded(query: query)
            }
            .store(in: &cancellables)
    }

    @Function(\Action.Cases.search)
    private func _search(_ query: String) async throws {
        guard searchQuery.value != query else { return }

        searchQuery.value = query

        await cancel()
    }

    func refreshSearch() {
        searchIfNeeded(query: searchQuery.value)
    }

    @Function(\Action.Cases.actuallySearch)
    private func _actuallySearch(_ query: String) async throws {

        guard self.canSearch else {
            resetSearchResults()
            return
        }

        let newItems = try await withThrowingTaskGroup(
            of: (BaseItemKind, [BaseItemDto]).self,
            returning: [BaseItemKind: [BaseItemDto]].self
        ) { group in

            // Base items
            let retrievingItemTypes: [BaseItemKind] = [
                .boxSet,
                .episode,
                .movie,
                .musicArtist,
                .musicVideo,
                .liveTvProgram,
                .series,
                .tvChannel,
                .video,
            ]

            for type in retrievingItemTypes {
                group.addTask {
                    let items = try await self._getItems(query: query, itemType: type)
                    return (type, items)
                }
            }

            // People
            group.addTask {
                let items = try await self._getPeople(query: query)
                return (BaseItemKind.person, items)
            }

            var result: [BaseItemKind: [BaseItemDto]] = [:]

            while let items = try await group.next() {
                if items.1.isNotEmpty {
                    result[items.0] = items.1
                }
            }

            return result
        }

        guard !Task.isCancelled else { return }
        self.items = newItems
        self.unifiedItems = newItems.mapValues { $0.map(UnifiedMediaResult.jellyfin) }

        guard seerSearchIsAvailable else {
            self._resetSeerItems()
            return
        }

        let seerResult = await SeerrClient.search(query: query)
        guard !Task.isCancelled else { return }
        switch seerResult {
        case let .success(page):
            self.seerItems = page.results
            self.mergeSeerResults(page.results)
        case .failure:
            self._resetSeerItems()
        }
    }

    private var seerSearchIsAvailable: Bool {
        SeerrIntegration.isAvailable
    }

    private func searchIfNeeded(query: String) {
        guard canSearch else {
            resetSearchResults()
            return
        }

        actuallySearch(query: query)
    }

    private func resetSearchResults() {
        if items.isNotEmpty {
            items.removeAll()
        }
        if seerItems.isNotEmpty {
            seerItems = []
        }
        if unifiedItems.isNotEmpty {
            unifiedItems.removeAll()
        }
    }

    private func mergeSeerResults(_ seerResults: [SeerrClient.MediaResult]) {
        var groupedSeer: [BaseItemKind: [SeerrClient.MediaResult]] = [:]
        for result in seerResults {
            guard let kind = UnifiedMediaResult.seerr(result).kind else { continue }
            guard kind != .person else { continue }
            groupedSeer[kind, default: []].append(result)
        }

        for (kind, typedSeerItems) in groupedSeer {
            let jellyfinItems = items[kind] ?? []
            var merged = jellyfinItems.map { item in
                UnifiedMediaResult.jellyfin(item)
            }

            let jellyfinSignatures = Set(jellyfinItems.map(SeerrLibraryMatcher.mediaSignature(for:)))
            let unmatchedSeer = typedSeerItems.filter {
                !jellyfinSignatures.contains(SeerrLibraryMatcher.mediaSignature(for: $0))
            }

            merged.append(contentsOf: unmatchedSeer.map { item in
                UnifiedMediaResult.seerr(item)
            })
            unifiedItems[kind] = merged
        }
    }

    private func _resetSeerItems() {
        self.seerItems = []
        for key in [BaseItemKind.movie, .series, .person] {
            unifiedItems[key] = items[key]?.map { item in
                UnifiedMediaResult.jellyfin(item)
            } ?? []
        }
    }

    func markSeerItemRequested(id: Int) {
        seerItems = seerItems.map { item in
            guard item.id == id else { return item }
            return item.updatingStatus(.pending)
        }

        unifiedItems = unifiedItems.mapValues { items in
            items.map { unifiedItem in
                guard case let .seerr(item) = unifiedItem else { return unifiedItem }
                guard item.id == id else { return unifiedItem }
                return .seerr(item.updatingStatus(.pending))
            }
        }
    }

    private func _getItems(query: String, itemType: BaseItemKind) async throws -> [BaseItemDto] {

        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.includeItemTypes = [itemType]
        parameters.isRecursive = true
        parameters.limit = 20
        parameters.searchTerm = query

        // Filters
        let filters = filterViewModel.currentFilters
        parameters.filters = filters.traits
        parameters.genres = filters.genres.map(\.value)
        parameters.sortBy = filters.sortBy
        parameters.sortOrder = filters.sortOrder
        parameters.tags = filters.tags.map(\.value)
        parameters.years = filters.years.map(\.intValue)

        if filters.letter.first?.value == "#" {
            parameters.nameLessThan = "A"
        } else {
            parameters.nameStartsWith = filters.letter
                .map(\.value)
                .filter { $0 != "#" }
                .first
        }

        let request = Paths.getItems(parameters: parameters)
        let response = try await send(request)

        let items = response.value.items ?? []
        guard itemType == .series else { return items }

        // Keep a standalone virtual/provider-backed series, but when Jellyfin
        // returns both a virtual shell and a concrete library series for the
        // same show, prefer the concrete item that owns the seasons.
        let concreteSeries = items.filter { !$0.isMissing }
        return items.filter { item in
            !item.isMissing || !concreteSeries.contains {
                seriesSearchItemsMatch(item, $0)
            }
        }
    }

    private func seriesSearchItemsMatch(_ lhs: BaseItemDto, _ rhs: BaseItemDto) -> Bool {
        let lhsTitle = normalizedSeriesSearchTitle(lhs)
        let rhsTitle = normalizedSeriesSearchTitle(rhs)
        guard lhsTitle.isNotEmpty, lhsTitle == rhsTitle else { return false }

        let lhsYear = lhs.productionYear ?? Int(lhs.premiereDateYear ?? "")
        let rhsYear = rhs.productionYear ?? Int(rhs.premiereDateYear ?? "")
        guard let lhsYear, let rhsYear else { return true }
        return lhsYear == rhsYear
    }

    private func normalizedSeriesSearchTitle(_ item: BaseItemDto) -> String {
        item.displayTitle
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func _getPeople(query: String) async throws -> [BaseItemDto] {

        var parameters = Paths.GetPersonsParameters()
        parameters.limit = 20
        parameters.searchTerm = query

        let request = Paths.getPersons(parameters: parameters)
        let response = try await send(request)

        return response.value.items ?? []
    }

    // MARK: suggestions

    @Function(\Action.Cases.getSuggestions)
    private func _getSuggestions() async throws {

        await filterViewModel.getQueryFilters()

        var parameters = Paths.GetItemsParameters()
        parameters.includeItemTypes = [.movie, .series]
        parameters.isRecursive = true
        parameters.limit = 10
        parameters.sortBy = [ItemSortBy.random]

        let request = Paths.getItems(parameters: parameters)
        let response = try await send(request)

        self.suggestions = response.value.items ?? []
    }
}
