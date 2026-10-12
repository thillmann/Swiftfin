//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import IdentifiedCollections
import JellyfinAPI

final class SeriesItemViewModel: ItemViewModel {

    enum SeasonsState {
        case initial
        case loading
        case content
        case error
    }

    @Published
    var seasons: IdentifiedArrayOf<SeasonItemViewModel> = []
    @Published
    private(set) var seasonsState: SeasonsState = .initial
    @Published
    private(set) var isLoadingPlayButtonItem = true
    @Published
    private(set) var episodeOverviewItem: BaseItemDto?
    @Published
    private(set) var upcomingEpisodePillLabel: String?

    private var upcomingEpisodePillTask: AnyCancellable?
    private var downloadEpisodesBySeasonID: [String: [BaseItemDto]] = [:]
    private var seriesRefreshTask: AnyCancellable?

    override var downloadActionAvailability: ItemDownloadActionAvailability {
        guard let seriesID = item.id else { return .unavailable }

        let summary = Container.shared.downloadManager().summary(forSeriesID: seriesID)
        if summary.totalCount > 0 {
            return .available
        }

        guard Container.shared.currentUserSession()?.user.data.policy?.enableContentDownloading == true else {
            return .unavailable
        }

        switch seasonsState {
        case .initial, .loading, .error:
            return .pending
        case .content:
            return seasons.isEmpty ? .unavailable : .available
        }
    }

    @MainActor
    func selectorSeasonID(for episode: BaseItemDto) -> SeasonItemViewModel.ID {
        if let seasonID = episode.seasonID ?? episode.parentID,
           seasons.contains(where: { $0.id == seasonID })
        {
            return seasonID
        }

        guard let seasonNumber = episode.parentIndexNumber else { return nil }

        return seasons.first(where: { $0.season.indexNumber == seasonNumber })?.id
    }

    // MARK: - Override Response

    override func respond(to action: ItemViewModel.Action) -> ItemViewModel.State {

        switch action {
        case .backgroundRefresh, .refresh:
            let parentState = super.respond(to: action)

            seriesRefreshTask?.cancel()
            seriesRefreshTask = Task { [weak self] in
                guard let self else { return }

                await MainActor.run {
                    self.seasons.removeAll()
                    self.seasonsState = .loading
                    self.isLoadingPlayButtonItem = true
                    self.downloadEpisodesBySeasonID.removeAll()
                    self.episodeOverviewItem = nil
                    self.upcomingEpisodePillLabel = nil
                }

                self.refreshUpcomingEpisodePillLabel()

                do {
                    // Prioritize the episode selector over secondary hero
                    // metadata. Search results contain only minimal fields and
                    // the initial full-item refresh runs at the same time, so
                    // retry one transient seasons failure after that refresh
                    // has had an opportunity to settle.
                    let newSeasons = try await getSeasonsWithInitialRetry()
                        .sorted { ($0.indexNumber ?? -1) < ($1.indexNumber ?? -1) }
                        .map(SeasonItemViewModel.init)

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.seasons.append(contentsOf: newSeasons)
                        self.seasonsState = .content
                    }

                    async let nextUp = try? getNextUp()
                    async let resume = try? getResumeItem()
                    async let firstAvailable = try? getFirstAvailableItem()

                    let (nextUpItem, resumeItem, firstAvailableItem) = await (
                        nextUp,
                        resume,
                        firstAvailable
                    )
                    guard !Task.isCancelled else { return }

                    let playButtonItem = [nextUpItem, resumeItem, firstAvailableItem].compacted().first
                    let episodeOverviewItem = featuredEpisodeOverviewItem(
                        for: playButtonItem,
                        nextUpItem: nextUpItem,
                        resumeItem: resumeItem,
                        firstAvailableItem: firstAvailableItem
                    )

                    await MainActor.run {
                        if let playButtonItem {
                            self.playButtonItem = playButtonItem
                        }

                        if let episodeOverviewItem {
                            self.episodeOverviewItem = episodeOverviewItem
                        }

                        self.isLoadingPlayButtonItem = false
                    }
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.seasonsState = .error
                        self.isLoadingPlayButtonItem = false
                    }
                }
            }
            .asAnyCancellable()
            return parentState

        default: ()
        }

        return super.respond(to: action)
    }

    private func refreshUpcomingEpisodePillLabel() {
        upcomingEpisodePillTask?.cancel()

        upcomingEpisodePillTask = Task { [weak self] in
            guard let self else { return }

            let label = await self.getUpcomingEpisodePillLabel()

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.upcomingEpisodePillLabel = label
            }
        }
        .asAnyCancellable()
    }

    private func featuredEpisodeOverviewItem(
        for playButtonItem: BaseItemDto?,
        nextUpItem: BaseItemDto?,
        resumeItem: BaseItemDto?,
        firstAvailableItem: BaseItemDto?
    ) -> BaseItemDto? {
        guard let playButtonItem else { return nil }

        if playButtonItem.isSameItem(as: resumeItem) {
            return playButtonItem
        }

        guard playButtonItem.isSameItem(as: nextUpItem) else { return nil }

        if playButtonItem.isSameItem(as: firstAvailableItem) {
            return nil
        }

        return playButtonItem
    }

    // MARK: - Get Next Up Item

    private func getNextUp() async throws -> BaseItemDto? {

        var parameters = Paths.GetNextUpParameters()
        parameters.fields = .MinimumFields
        parameters.seriesID = item.id

        let request = Paths.getNextUp(parameters: parameters)
        let response = try await send(request)

        guard let item = response.value.items?.first, !item.isMissing else {
            return nil
        }

        return item
    }

    // MARK: - Get Resumable Item

    private func getResumeItem() async throws -> BaseItemDto? {

        var parameters = Paths.GetResumeItemsParameters()
        parameters.fields = .MinimumFields
        parameters.limit = 1
        parameters.parentID = item.id

        let request = Paths.getResumeItems(parameters: parameters)
        let response = try await send(request)

        return response.value.items?.first
    }

    // MARK: - Get First Available Item

    private func getFirstAvailableItem() async throws -> BaseItemDto? {

        var parameters = Paths.GetItemsParameters()
        parameters.fields = .MinimumFields
        parameters.includeItemTypes = [.episode]
        parameters.isRecursive = true
        parameters.limit = 1
        parameters.parentID = item.id
        parameters.sortOrder = [.ascending]

        let request = Paths.getItems(parameters: parameters)
        let response = try await send(request)

        return response.value.items?.first
    }

    /// Fetch complete episode metadata and ordered media sources for a
    /// show-level offline download.
    func getEpisodesForDownload() async throws -> [BaseItemDto] {
        guard let seriesID = item.id else { return [] }

        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        // Load only episode metadata here. Each episode resolves its complete
        // item-scoped source catalogue immediately before it is enqueued.
        parameters.fields = .MinimumFields
        parameters.includeItemTypes = [.episode]
        // Provider-backed episodes can be marked virtual by Jellyfin while
        // still resolving to finite downloadable HTTP media sources.
        parameters.isMissing = nil
        parameters.isRecursive = true
        parameters.limit = 10000
        parameters.parentID = seriesID
        parameters.sortOrder = [.ascending]

        let response = try await send(Paths.getItems(parameters: parameters))
        return response.value.items ?? []
    }

    /// Lazily loads the download metadata for one season. The result is kept
    /// for the lifetime of this series view model so navigating back and forth
    /// in the download picker does not repeat a potentially expensive request.
    func getEpisodesForDownload(in season: BaseItemDto) async throws -> [BaseItemDto] {
        guard let seriesID = item.id, let seasonID = season.id else { return [] }

        if let cached = downloadEpisodesBySeasonID[seasonID] {
            return cached
        }

        var parameters = Paths.GetEpisodesParameters()
        parameters.enableUserData = true
        // Load the episode list only. Version discovery is intentionally
        // deferred until the user starts an episode or season download so
        // availability and signed provider data are current at selection time.
        parameters.fields = .MinimumFields
        // Do not use Jellyfin's virtual/missing metadata as a downloadability
        // check. The source resolver is the authority for provider content.
        parameters.isMissing = nil
        parameters.seasonID = seasonID

        let response = try await send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters))
        let episodes = (response.value.items ?? [])
            .sorted { ($0.indexNumber ?? -1) < ($1.indexNumber ?? -1) }
        downloadEpisodesBySeasonID[seasonID] = episodes
        return episodes
    }

    func episodeResolvingDownloadSources(_ episode: BaseItemDto) async -> BaseItemDto {
        guard let episodeID = episode.id, let userSession else { return episode }

        do {
            return try await userSession.client
                .send(
                    Paths.getItem(
                        itemID: episodeID,
                        userID: userSession.user.id
                    ),
                    configure: { request in
                        request.timeoutInterval = ItemViewModel.mediaSourceCatalogueRequestTimeout
                    }
                )
                .value
        } catch {
            return episode
        }
    }

    // MARK: - Get Upcoming Episode

    private func getUpcomingEpisodePillLabel() async -> String? {
        guard let userSession else {
            return nil
        }

        return await UpcomingEpisodeProvider.pillLabel(for: item, userSession: userSession)
    }

    // MARK: - Get First Item Seasons

    private func getSeasonsWithInitialRetry() async throws -> [BaseItemDto] {
        do {
            return try await getSeasons()
        } catch {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(350))
            return try await getSeasons()
        }
    }

    private func getSeasons() async throws -> [BaseItemDto] {
        guard let itemID = item.id else { return [] }

        let shouldShowMissingSeasons = Defaults[.Customization.shouldShowMissingSeasons]
        var parameters = Paths.GetSeasonsParameters()
        parameters.isMissing = shouldShowMissingSeasons ? nil : false

        var request = Paths.getSeasons(
            seriesID: itemID,
            parameters: parameters
        )
        var response = try await send(request)

        // Provider-backed seasons can be marked virtual despite containing
        // playable episodes. If filtering virtual items empties an otherwise
        // valid library series, retry without that filter.
        if response.value.items?.isEmpty != false, !shouldShowMissingSeasons {
            parameters.isMissing = nil
            request = Paths.getSeasons(seriesID: itemID, parameters: parameters)
            response = try await send(request)
        }

        return response.value.items ?? []
    }
}

private extension BaseItemDto {

    func isSameItem(as other: BaseItemDto?) -> Bool {
        guard let other else { return false }

        if let id, let otherID = other.id {
            return id == otherID
        }

        return parentIndexNumber == other.parentIndexNumber && indexNumber == other.indexNumber
    }
}
