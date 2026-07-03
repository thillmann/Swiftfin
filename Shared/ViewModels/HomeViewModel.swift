//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import CoreStore
import Factory
import Get
import JellyfinAPI
import OrderedCollections

@MainActor
final class HomeViewModel: ViewModel, Stateful {

    #if os(tvOS)
    struct Genre: Hashable, Identifiable {
        let id: String
        let genre: MediaGenre
        let itemTypes: [BaseItemKind]

        init(
            genre: MediaGenre,
            idPrefix: String,
            itemTypes: [BaseItemKind]
        ) {
            self.id = "\(idPrefix)-\(genre.id)"
            self.genre = genre
            self.itemTypes = itemTypes
        }

        var displayTitle: String {
            genre.displayTitle
        }

        var imageSources: [ImageSource] {
            genre.artworkImageSources
        }
    }
    #endif

    // MARK: Action

    enum Action: Equatable {
        case backgroundRefresh
        case error(ErrorMessage)
        case setIsPlayed(Bool, BaseItemDto)
        case refresh
        case toggleIsFavorite(BaseItemDto)
    }

    // MARK: BackgroundState

    enum BackgroundState: Hashable {
        case refresh
    }

    // MARK: State

    enum State: Hashable {
        case content
        case error(ErrorMessage)
        case initial
        case refreshing
    }

    @Published
    private(set) var libraries: [LatestInLibraryViewModel] = []
    #if os(tvOS)
    @Published
    private(set) var movieGenres: [Genre] = []
    @Published
    private(set) var tvShowGenres: [Genre] = []
    @Published
    private(set) var upcomingMovies: [UnifiedMediaResult] = []
    @Published
    private(set) var upcomingTVShows: [UnifiedMediaResult] = []
    #endif
    @Published
    var resumeItems: OrderedSet<BaseItemDto> = []

    @Published
    var backgroundStates: Set<BackgroundState> = []
    @Published
    var state: State = .initial

    // TODO: replace with views checking what notifications were
    //       posted since last disappear
    @Published
    var notificationsReceived: NotificationSet = .init()

    private var backgroundRefreshTask: AnyCancellable?
    private var refreshTask: AnyCancellable?

    var nextUpViewModel: NextUpLibraryViewModel = .init()
    var recentlyAddedViewModel: RecentlyAddedLibraryViewModel = .init()

    override init() {
        super.init()

        Notifications[.itemMetadataDidChange]
            .publisher
            .sink { item in
                // Necessary because when this notification is posted, even with asyncAfter,
                // the view will cause layout issues since it will redraw while in landscape.
                // TODO: look for better solution
                DispatchQueue.main.async {
                    self.updateResumeItem(with: item)
                    self.notificationsReceived.insert(.itemMetadataDidChange)
                }
            }
            .store(in: &cancellables)
    }

    func respond(to action: Action) -> State {
        switch action {
        case .backgroundRefresh:

            backgroundRefreshTask?.cancel()
            backgroundStates.insert(.refresh)

            backgroundRefreshTask = Task { [weak self] in
                do {
                    self?.nextUpViewModel.send(.refresh)
                    self?.recentlyAddedViewModel.send(.refresh)
                    #if os(tvOS)
                    await self?.loadUpcomingMedia()
                    #endif

                    let resumeItems = try await self?.getResumeItems() ?? []

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard let self else { return }
                        self.resumeItems.elements = resumeItems
                        #if os(tvOS)
                        if let userSession = self.userSession {
                            TopShelfResumeCacheWriter.write(
                                items: resumeItems,
                                userSession: userSession
                            )
                        }
                        #endif
                        self.backgroundStates.remove(.refresh)
                    }
                } catch is CancellationError {
                    // cancelled
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard let self else { return }
                        self.backgroundStates.remove(.refresh)
                        self.send(.error(.init(error.localizedDescription)))
                    }
                }
            }
            .asAnyCancellable()

            return state
        case let .error(error):
            return .error(error)
        case let .setIsPlayed(isPlayed, item): ()
            Task {
                try await setIsPlayed(isPlayed, for: item)

                self.send(.backgroundRefresh)
            }
            .store(in: &cancellables)

            return state
        case .refresh:
            backgroundRefreshTask?.cancel()
            refreshTask?.cancel()

            refreshTask = Task { [weak self] in
                do {
                    try await self?.refresh()

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard let self else { return }
                        self.state = .content
                    }
                } catch is CancellationError {
                    // cancelled
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard let self else { return }
                        self.send(.error(.init(error.localizedDescription)))
                    }
                }
            }
            .asAnyCancellable()

            #if os(tvOS)
            return state == .initial ? .refreshing : state
            #else
            return .refreshing
            #endif
        case let .toggleIsFavorite(item):

            Task {
                let beforeIsFavorite = item.userData?.isFavorite ?? false

                await MainActor.run {
                    setResumeItem(item.id, isFavorite: !beforeIsFavorite)
                }

                do {
                    try await setIsFavorite(!beforeIsFavorite, for: item)
                } catch {
                    await MainActor.run {
                        setResumeItem(item.id, isFavorite: beforeIsFavorite)
                    }
                }
            }
            .store(in: &cancellables)

            return state
        }
    }

    private func refresh() async throws {

        await nextUpViewModel.send(.refresh)
        await recentlyAddedViewModel.send(.refresh)
        #if os(tvOS)
        await loadUpcomingMedia()
        #endif

        let resumeItems = try await getResumeItems()
        #if os(tvOS)
        let fetchedLibraries = try await getLibraries()
        let libraries = fetchedLibraries.map { fetchedLibrary in
            self.libraries.first { library in
                library.parent?.id == fetchedLibrary.parent?.id
            } ?? fetchedLibrary
        }
        #else
        let libraries = try await getLibraries()
        #endif

        for library in libraries {
            await library.send(.refresh)
        }

        try Task.checkCancellation()

        await MainActor.run {
            self.resumeItems.elements = resumeItems
            #if os(tvOS)
            if let userSession {
                TopShelfResumeCacheWriter.write(
                    items: resumeItems,
                    userSession: userSession
                )
            }
            #endif
            self.libraries = libraries
        }

        try Task.checkCancellation()

        #if os(tvOS)
        loadGenres()
        #endif
    }

    private func getResumeItems() async throws -> [BaseItemDto] {
        var parameters = Paths.GetResumeItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.mediaTypes = [.video]
        parameters.limit = 20

        let request = Paths.getResumeItems(parameters: parameters)
        let response = try await send(request)
        let items = response.value.items ?? []

        #if os(tvOS)
        return Array(
            items.lazy
                .filter { !self.isLikelyInCredits($0) }
                .prefix(8)
        )
        #else
        return items
        #endif
    }

    private func setResumeItem(_ itemID: String?, isFavorite: Bool) {
        guard let itemID,
              let index = resumeItems.elements.firstIndex(where: { $0.id == itemID })
        else { return }

        var elements = resumeItems.elements
        elements[index].userData?.isFavorite = isFavorite
        resumeItems.elements = elements
    }

    private func updateResumeItem(with item: BaseItemDto) {
        guard let itemID = item.id,
              let index = resumeItems.elements.firstIndex(where: { $0.id == itemID })
        else { return }

        var elements = resumeItems.elements
        elements[index] = item
        resumeItems.elements = elements
    }

    #if os(tvOS)
    private func isLikelyInCredits(_ item: BaseItemDto) -> Bool {
        guard let runTimeTicks = item.runTimeTicks,
              runTimeTicks > 0,
              let playbackPositionTicks = item.userData?.playbackPositionTicks,
              playbackPositionTicks > 0
        else {
            return false
        }

        let remainingTicks = max(0, runTimeTicks - playbackPositionTicks)
        let watchedFraction = Double(playbackPositionTicks) / Double(runTimeTicks)

        return watchedFraction >= 0.9 && remainingTicks <= Duration.minutes(5).ticks
    }
    #endif

    private func getLibraries() async throws -> [LatestInLibraryViewModel] {

        let parameters = try Paths.GetUserViewsParameters(userID: authenticatedUser.id)
        let userViewsPath = Paths.getUserViews(parameters: parameters)
        async let userViews = try await send(userViewsPath)

        async let excludedLibraryIDs = getExcludedLibraries()

        return try await (userViews.value.items ?? [])
            .intersecting(
                [
                    .homevideos,
                    .movies,
                    .musicvideos,
                    .tvshows,
                ],
                using: \.collectionType
            )
            .subtracting(excludedLibraryIDs, using: \.id)
            .map { LatestInLibraryViewModel(parent: $0) }
    }

    #if os(tvOS)
    private func loadGenres() {
        movieGenres = GenreTaxonomy.movieGenres.map { genre in
            Genre(
                genre: genre,
                idPrefix: "movie",
                itemTypes: [.movie]
            )
        }

        tvShowGenres = GenreTaxonomy.tvShowGenres.map { genre in
            Genre(
                genre: genre,
                idPrefix: "tv",
                itemTypes: [.series]
            )
        }
    }

    func markUpcomingRequested(_ requestedItem: SeerrClient.MediaResult) {
        upcomingMovies = updateRequestStatus(for: upcomingMovies, requestedItem: requestedItem)
        upcomingTVShows = updateRequestStatus(for: upcomingTVShows, requestedItem: requestedItem)
    }

    private func loadUpcomingMedia() async {
        guard SeerrIntegration.isAvailable else {
            upcomingMovies = []
            upcomingTVShows = []
            return
        }

        let movies = await loadUpcomingItems { page in
            await SeerrClient.discoverUpcomingMovies(page: page, language: "en")
        }
        let tvShows = await loadUpcomingItems { page in
            await SeerrClient.discoverUpcomingTV(page: page, language: "en")
        }

        upcomingMovies = unifiedUpcomingItems(from: movies)
        upcomingTVShows = unifiedUpcomingItems(from: tvShows)
    }

    private func loadUpcomingItems(
        using discover: (Int) async -> Result<SeerrClient.Page<SeerrClient.MediaResult>, SeerrClient.ProbeError>
    ) async -> [SeerrClient.MediaResult] {
        let pageLimit = 5
        let firstPageResult = await discover(1)

        guard case let .success(firstPage) = firstPageResult else { return [] }

        var results = firstPage.results
        let lastPage = min(firstPage.totalPages ?? 1, pageLimit)

        if lastPage > 1 {
            for page in 2 ... lastPage {
                let pageResult = await discover(page)

                guard case let .success(response) = pageResult else { return results }

                results.append(contentsOf: response.results)
            }
        }

        return results
    }

    private func unifiedUpcomingItems(from results: [SeerrClient.MediaResult]) -> [UnifiedMediaResult] {
        sortByReleaseDate(
            deduplicated(
                results.filter { $0.originalLanguage == "en" }
            )
            .map(UnifiedMediaResult.seerr)
        )
    }

    private func deduplicated(_ results: [SeerrClient.MediaResult]) -> [SeerrClient.MediaResult] {
        var seenIDs = Set<String>()

        return results.filter { item in
            seenIDs.insert(SeerrLibraryMatcher.key(for: item)).inserted
        }
    }

    private func sortByReleaseDate(_ items: [UnifiedMediaResult]) -> [UnifiedMediaResult] {
        items.sorted { lhs, rhs in
            let lhsDate = releaseDate(for: lhs)
            let rhsDate = releaseDate(for: rhs)

            switch (lhsDate, rhsDate) {
            case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                return lhsDate < rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.id < rhs.id
            }
        }
    }

    private func releaseDate(for item: UnifiedMediaResult) -> String? {
        guard case let .seerr(item) = item else { return nil }
        guard let date = item.releaseDate ?? item.firstAirDate, date.isNotEmpty else { return nil }
        return date
    }

    private func updateRequestStatus(
        for items: [UnifiedMediaResult],
        requestedItem: SeerrClient.MediaResult
    ) -> [UnifiedMediaResult] {
        items.map { item in
            guard case let .seerr(seerrItem) = item,
                  seerrItem.id == requestedItem.id,
                  seerrItem.mediaType == requestedItem.mediaType
            else {
                return item
            }

            return .seerr(seerrItem.updatingStatus(.pending))
        }
    }
    #endif

    // TODO: use the more updated server/user data when implemented
    private func getExcludedLibraries() async throws -> [String] {
        let currentUserPath = Paths.getCurrentUser
        let response = try await send(currentUserPath)

        return response.value.configuration?.latestItemsExcludes ?? []
    }

    private func setIsPlayed(_ isPlayed: Bool, for item: BaseItemDto) async throws {
        guard let itemID = item.id else { return }

        let request: Request<UserItemDataDto> = if isPlayed {
            try Paths.markPlayedItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        } else {
            try Paths.markUnplayedItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        }

        _ = try await send(request)
    }

    private func setIsFavorite(_ isFavorite: Bool, for item: BaseItemDto) async throws {
        guard let itemID = item.id else { return }
        let user = try authenticatedUser

        let request: Request<UserItemDataDto> = if isFavorite {
            Paths.markFavoriteItem(
                itemID: itemID,
                userID: user.id
            )
        } else {
            Paths.unmarkFavoriteItem(
                itemID: itemID,
                userID: user.id
            )
        }

        _ = try await send(request)
        Notifications[.itemShouldRefreshMetadata].post(itemID)
    }
}
