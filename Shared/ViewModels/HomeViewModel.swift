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
        let genre: ItemGenre
        let itemCount: Int
        let posterItem: BaseItemDto

        var id: String {
            genre.id ?? genre.value
        }

        var displayTitle: String {
            genre.displayTitle
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
    private(set) var genres: [Genre] = []
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
    #if os(tvOS)
    private var genresTask: AnyCancellable?
    #endif

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
            #if os(tvOS)
            genresTask?.cancel()
            #endif

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
        loadGenres(in: libraries)
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
    private func loadGenres(in libraries: [LatestInLibraryViewModel]) {
        genresTask?.cancel()

        genresTask = Task { [weak self] in
            guard let self else { return }

            let genres = await (try? self.getGenres(in: libraries)) ?? []
            guard !Task.isCancelled else { return }

            self.genres = genres
        }
        .asAnyCancellable()
    }

    private func getGenres(in libraries: [LatestInLibraryViewModel]) async throws -> [Genre] {
        let userID = try authenticatedUser.id
        var genresByID: [String: Genre] = [:]

        for library in libraries {
            guard let parent = library.parent as? BaseItemDto else { continue }

            let parameters = Paths.GetQueryFiltersParameters(
                userID: userID,
                parentID: parent.id,
                includeItemTypes: parent.supportedItemTypes,
                isRecursive: parent.isRecursiveCollection
            )

            let request = Paths.getQueryFilters(parameters: parameters)
            let response = try await send(request)

            for genre in response.value.genres ?? [] {
                guard let name = genre.name else { continue }
                let itemGenre = ItemGenre(name, id: genre.id)
                let key = itemGenre.id ?? itemGenre.value

                guard genresByID[key] == nil else { continue }

                let preview = try? await preview(for: itemGenre)

                guard let preview else { continue }

                genresByID[key] = Genre(
                    genre: itemGenre,
                    itemCount: preview.itemCount,
                    posterItem: preview.posterItem
                )
            }
        }

        return genresByID.values
            .sorted { lhs, rhs in
                lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    private func preview(for genre: ItemGenre) async throws -> (itemCount: Int, posterItem: BaseItemDto)? {
        let parent = TitledLibraryParent(
            displayTitle: genre.displayTitle,
            id: genre.id ?? genre.value
        )
        let viewModel = ItemLibraryViewModel(
            parent: parent,
            filters: .init(
                genres: [genre],
                itemTypes: [.movie, .series],
                sortBy: [.random]
            )
        )

        let items = try await viewModel.get(page: 0)
        guard let posterItem = items.randomElement() else { return nil }

        return (items.count, posterItem)
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
