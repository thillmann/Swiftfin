//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import JellyfinAPI
import OrderedCollections
import SwiftUI

enum UnifiedSearchResult: Identifiable {
    enum Source: Hashable {
        case jellyfin
        case seer
    }

    case jellyfin(BaseItemDto)
    case seer(SeerrClient.MediaResult)

    var id: String {
        switch self {
        case let .jellyfin(item):
            "jellyfin-\(item.id ?? item.displayTitle)"
        case let .seer(item):
            "seer-\(item.id)"
        }
    }

    var kind: BaseItemKind? {
        switch self {
        case let .jellyfin(item):
            item.type
        case let .seer(item):
            switch item.mediaType {
            case .movie:
                .movie
            case .tv:
                .series
            case .person:
                .person
            case nil:
                nil
            }
        }
    }

    var title: String {
        switch self {
        case let .jellyfin(item):
            item.displayTitle
        case let .seer(item):
            item.title ?? item.name ?? L10n.unknown
        }
    }

    var source: Source {
        switch self {
        case .jellyfin:
            .jellyfin
        case .seer:
            .seer
        }
    }

    var imageSources: [ImageSource] {
        switch self {
        case let .jellyfin(item):
            item.thumbImageSources()
        case let .seer(item):
            [item.posterImageSource]
        }
    }

    var hasSeerPoster: Bool {
        guard case let .seer(item) = self else { return false }
        guard let posterPath = item.posterPath else { return false }
        return !posterPath.isEmpty
    }
}

extension UnifiedSearchResult: Hashable {
    static func == (lhs: UnifiedSearchResult, rhs: UnifiedSearchResult) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension UnifiedSearchResult: Displayable {
    var displayTitle: String {
        title
    }
}

extension UnifiedSearchResult: LibraryIdentifiable {
    var unwrappedIDHashOrZero: Int {
        id.hashValue
    }
}

extension UnifiedSearchResult: SystemImageable {
    var systemImage: String {
        switch self {
        case let .jellyfin(item):
            item.systemImage
        case let .seer(item):
            switch item.mediaType {
            case .movie:
                "film"
            case .tv:
                "tv"
            case .person:
                "person"
            case nil:
                "questionmark"
            }
        }
    }
}

extension UnifiedSearchResult: Poster {
    var preferredPosterDisplayType: PosterDisplayType {
        switch kind {
        case .person:
            .portrait
        case .movie, .series:
            .portrait
        default:
            .portrait
        }
    }

    func portraitImageSources(maxWidth _: CGFloat?, quality _: Int?) -> [ImageSource] {
        imageSources
    }

    func landscapeImageSources(maxWidth _: CGFloat?, quality _: Int?) -> [ImageSource] {
        imageSources
    }

    func cinematicImageSources(maxWidth _: CGFloat?, quality _: Int?) -> [ImageSource] {
        imageSources
    }

    func squareImageSources(maxWidth _: CGFloat?, quality _: Int?) -> [ImageSource] {
        imageSources
    }

    @MainActor
    func transform(image: Image) -> some View {
        ZStack(alignment: .topTrailing) {
            image

            if source == .seer, hasSeerPoster {
                Image("seerr.monochrome")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .padding(.top, 8)
                    .padding(.trailing, 8)
            }

            if let seerStatusPillText {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(seerStatusPillText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Defaults[.accentColor], in: Capsule())
                    }
                }
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
        }
    }

    var subtitle: String? {
        nil
    }

    private var seerStatusPillText: String? {
        guard case let .seer(item) = self else { return nil }
        guard let status = item.mediaInfo?.mediaStatus else { return nil }
        guard status != .unknown else { return nil }

        return switch status {
        case .pending:
            "Requested"
        case .processing:
            "Processing"
        case .partiallyAvailable:
            "Partial"
        case .available:
            "Available"
        case .unknown:
            nil
        }
    }
}

@MainActor
@Stateful
final class SearchViewModel: ViewModel {
    @CasePathable
    enum Action {
        case getSuggestions
        case search(query: String)
        case actuallySearch(query: String)

        var transition: Transition {
            switch self {
            case .getSuggestions:
                .none
            case let .search(query):
                query.isEmpty ? .to(.initial) : .to(.searching)
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
    private(set) var unifiedItems: [BaseItemKind: [UnifiedSearchResult]] = [:]
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
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self else { return }

                actuallySearch(query: query)
            }
            .store(in: &cancellables)

        filterViewModel.$currentFilters
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }

                actuallySearch(query: searchQuery.value)
            }
            .store(in: &cancellables)
    }

    @Function(\Action.Cases.search)
    private func _search(_ query: String) async throws {
        searchQuery.value = query

        await cancel()
    }

    @Function(\Action.Cases.actuallySearch)
    private func _actuallySearch(_ query: String) async throws {

        guard self.canSearch else {
            items.removeAll()
            seerItems = []
            unifiedItems.removeAll()
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
        self.unifiedItems = newItems.mapValues { $0.map(UnifiedSearchResult.jellyfin) }

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
            logger.debug("Seerr search query='\(query)' failed")
        }
    }

    private var seerSearchIsAvailable: Bool {
        Defaults[.Integrations.Seerr.isEnabled]
            && SeerrIntegration.serverURL != nil
            && SeerrIntegration.apiKey != nil
    }

    private func mergeSeerResults(_ seerResults: [SeerrClient.MediaResult]) {
        var groupedSeer: [BaseItemKind: [SeerrClient.MediaResult]] = [:]
        for result in seerResults {
            guard let kind = UnifiedSearchResult.seer(result).kind else { continue }
            guard kind != .person else { continue }
            groupedSeer[kind, default: []].append(result)
        }

        for (kind, typedSeerItems) in groupedSeer {
            let jellyfinItems = items[kind] ?? []
            var merged = jellyfinItems.map { item in
                UnifiedSearchResult.jellyfin(item)
            }

            let jellyfinSignatures = Set(jellyfinItems.map(seerSignature(for:)))
            let unmatchedSeer = typedSeerItems.filter { !jellyfinSignatures.contains(seerSignature(for: $0)) }

            merged.append(contentsOf: unmatchedSeer.map { item in
                UnifiedSearchResult.seer(item)
            })
            unifiedItems[kind] = merged
        }
    }

    private func seerSignature(for jellyfinItem: BaseItemDto) -> String {
        let normalizedTitle = jellyfinItem.displayTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let year = jellyfinItem.productionYear ?? Int(jellyfinItem.premiereDateYear ?? "")
        return "\(normalizedTitle)-\(year ?? 0)"
    }

    private func seerSignature(for seerItem: SeerrClient.MediaResult) -> String {
        let normalizedTitle = (seerItem.title ?? seerItem.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let year = Int((seerItem.releaseDate ?? seerItem.firstAirDate ?? "").prefix(4))
        return "\(normalizedTitle)-\(year ?? 0)"
    }

    private func _resetSeerItems() {
        self.seerItems = []
        for key in [BaseItemKind.movie, .series, .person] {
            unifiedItems[key] = items[key]?.map { item in
                UnifiedSearchResult.jellyfin(item)
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
                guard case let .seer(item) = unifiedItem else { return unifiedItem }
                guard item.id == id else { return unifiedItem }
                return .seer(item.updatingStatus(.pending))
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

        return response.value.items ?? []
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
