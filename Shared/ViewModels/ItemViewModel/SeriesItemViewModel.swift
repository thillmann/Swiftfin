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

                do {
                    async let nextUp = getNextUp()
                    async let resume = getResumeItem()
                    async let firstAvailable = getFirstAvailableItem()
                    async let seasons = getSeasons()
                    async let upcomingEpisodePillLabel = getUpcomingEpisodePillLabel()

                    let newSeasons = try await seasons
                        .sorted { ($0.indexNumber ?? -1) < ($1.indexNumber ?? -1) }
                        .map(SeasonItemViewModel.init)

                    await MainActor.run {
                        self.seasons.append(contentsOf: newSeasons)
                    }

                    let nextUpItem = try await nextUp
                    let resumeItem = try await resume
                    let firstAvailableItem = try await firstAvailable
                    let newUpcomingEpisodePillLabel = await upcomingEpisodePillLabel

                    if let playButtonItem = [nextUpItem, resumeItem, firstAvailableItem].compacted().first {
                        await MainActor.run {
                            self.playButtonItem = playButtonItem
                        }
                    }

                    let episodeOverviewItem: BaseItemDto? = {
                        if let resumeItem {
                            return resumeItem
                        }

                        guard let nextUpItem else { return nil }

                        guard let firstAvailableItem else {
                            return nextUpItem
                        }

                        if let nextUpID = nextUpItem.id,
                           let firstAvailableID = firstAvailableItem.id,
                           nextUpID == firstAvailableID
                        {
                            return nil
                        }

                        if nextUpItem.parentIndexNumber == firstAvailableItem.parentIndexNumber,
                           nextUpItem.indexNumber == firstAvailableItem.indexNumber
                        {
                            return nil
                        }

                        return nextUpItem
                    }()

                    if let episodeOverviewItem {
                        await MainActor.run {
                            self.episodeOverviewItem = episodeOverviewItem
                        }
                    }

                    await MainActor.run {
                        self.upcomingEpisodePillLabel = newUpcomingEpisodePillLabel
                    }
                }
            }
            .store(in: &cancellables)
        default: ()
        }

        return super.respond(to: action)
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
        if let jellyfinUpcomingEpisode = await getJellyfinUpcomingEpisode() {
            if let label = jellyfinUpcomingEpisode.upcomingEpisodePillLabel {
                return label
            }
        }

        return await getSeerrUpcomingEpisodePillLabel()
    }

    private func getJellyfinUpcomingEpisode() async -> BaseItemDto? {

        let startOfToday = Calendar.current.startOfDay(for: Date())
        let attempts: [(label: String, isMissing: Bool?, isUnaired: Bool?)] = [
            ("unaired", nil, true),
            ("missing", true, nil),
            ("future", nil, nil),
        ]

        for attempt in attempts {
            if let item = await getUpcomingEpisode(
                attempt: attempt.label,
                isMissing: attempt.isMissing,
                isUnaired: attempt.isUnaired,
                minPremiereDate: startOfToday
            ) {
                return item
            }
        }

        return nil
    }

    private func getSeerrUpcomingEpisodePillLabel() async -> String? {
        guard SeerrIntegration.isAvailable else {
            return nil
        }

        let providerItem = await itemWithProviderIDs()

        guard let tmdbID = providerItem.tmdbProviderID else {
            return nil
        }

        let result = await SeerrClient.tvDetails(id: tmdbID)

        switch result {
        case let .success(details):
            guard let nextEpisode = details.nextEpisodeToAir else {
                return nil
            }

            guard let label = nextEpisode.upcomingEpisodePillLabel else {
                return nil
            }

            return label
        case let .failure(error):
            return nil
        }
    }

    private func itemWithProviderIDs() async -> BaseItemDto {
        if item.tmdbProviderID != nil {
            return item
        }

        do {
            return try await item.getFullItem(userSession: userSession)
        } catch {
            return item
        }
    }

    private func getUpcomingEpisode(
        attempt: String,
        isMissing: Bool?,
        isUnaired: Bool?,
        minPremiereDate: Date
    ) async -> BaseItemDto? {

        var parameters = Paths.GetItemsParameters()
        parameters.enableTotalRecordCount = true
        parameters.fields = .MinimumFields
        parameters.includeItemTypes = [.episode]
        parameters.isRecursive = true
        parameters.isMissing = isMissing
        parameters.isUnaired = isUnaired
        parameters.limit = 1
        parameters.minPremiereDate = minPremiereDate
        parameters.parentID = item.id
        parameters.sortBy = [.premiereDate]
        parameters.sortOrder = [.ascending]

        let request = Paths.getItems(parameters: parameters)

        do {
            let response = try await userSession.client.send(request)
            let items = response.value.items ?? []

            guard let firstItem = items.first else {
                return nil
            }

            return firstItem
        } catch {
            return nil
        }
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

    var tmdbProviderID: Int? {
        guard let providerID = providerIDs?.first(where: { providerID in
            providerID.key.compare("Tmdb", options: .caseInsensitive) == .orderedSame
        }) else {
            return nil
        }

        return Int(providerID.value)
    }

    var upcomingEpisodePillLabel: String? {
        guard let premiereDate else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"

        return "New Episode on \(formatter.string(from: premiereDate))"
    }
}

private extension SeerrClient.TVDetails.Episode {

    var upcomingEpisodePillLabel: String? {
        guard let airDate else { return nil }

        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"

        guard let date = parser.date(from: airDate) else {
            return "New Episode on \(airDate)"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"

        return "New Episode on \(formatter.string(from: date))"
    }
}
