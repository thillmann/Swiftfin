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
import IdentifiedCollections
import JellyfinAPI

final class SeriesItemViewModel: ItemViewModel {

    @Published
    var seasons: IdentifiedArrayOf<SeasonItemViewModel> = []
    @Published
    private(set) var episodeOverviewItem: BaseItemDto?
    @Published
    private(set) var upcomingEpisodePillLabel: String?

    private var upcomingEpisodePillTask: AnyCancellable?

    // MARK: - Override Response

    override func respond(to action: ItemViewModel.Action) -> ItemViewModel.State {

        switch action {
        case .backgroundRefresh, .refresh:
            let parentState = super.respond(to: action)

            Task { [weak self] in
                guard let self else { return }

                await MainActor.run {
                    self.seasons.removeAll()
                    self.episodeOverviewItem = nil
                    self.upcomingEpisodePillLabel = nil
                }

                self.refreshUpcomingEpisodePillLabel()

                do {
                    async let nextUp = getNextUp()
                    async let resume = getResumeItem()
                    async let firstAvailable = getFirstAvailableItem()
                    async let seasons = getSeasons()

                    let newSeasons = try await seasons
                        .sorted { ($0.indexNumber ?? -1) < ($1.indexNumber ?? -1) }
                        .map(SeasonItemViewModel.init)

                    await MainActor.run {
                        self.seasons.append(contentsOf: newSeasons)
                    }

                    let nextUpItem = try await nextUp
                    let resumeItem = try await resume
                    let firstAvailableItem = try await firstAvailable
                    let playButtonItem = [nextUpItem, resumeItem, firstAvailableItem].compacted().first
                    let episodeOverviewItem = featuredEpisodeOverviewItem(
                        for: playButtonItem,
                        nextUpItem: nextUpItem,
                        resumeItem: resumeItem,
                        firstAvailableItem: firstAvailableItem
                    )

                    if let playButtonItem {
                        await MainActor.run {
                            self.playButtonItem = playButtonItem
                        }
                    }

                    if let episodeOverviewItem {
                        await MainActor.run {
                            self.episodeOverviewItem = episodeOverviewItem
                        }
                    }
                }
            }
            .store(in: &cancellables)
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

    // MARK: - Get Upcoming Episode

    private func getUpcomingEpisodePillLabel() async -> String? {
        guard let userSession else {
            return nil
        }

        return await SeerrIntegration.upcomingEpisodePillLabel(for: item, userSession: userSession)
    }

    // MARK: - Get First Item Seasons

    private func getSeasons() async throws -> [BaseItemDto] {
        guard let itemID = item.id else { return [] }

        var parameters = Paths.GetSeasonsParameters()
        parameters.isMissing = Defaults[.Customization.shouldShowMissingSeasons] ? nil : false

        let request = Paths.getSeasons(
            seriesID: itemID,
            parameters: parameters
        )
        let response = try await send(request)

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
