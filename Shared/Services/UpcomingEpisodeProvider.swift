//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

enum UpcomingEpisodeProvider {

    static func pillLabel(for item: BaseItemDto, userSession: UserSession) async -> String? {
        guard let seriesItem = await seriesItem(for: item, userSession: userSession) else { return nil }

        if let upcomingEpisode = await getUpcomingEpisode(
            seriesID: seriesItem.id,
            userSession: userSession
        ), let premiereDate = upcomingEpisode.premiereDate,
        premiereDate > Date() {
            return premiereDate.upcomingEpisodePillLabel
        }

        return await SeerrIntegration.upcomingEpisodePillLabel(
            for: seriesItem,
            userSession: userSession
        )
    }

    private static func seriesItem(
        for item: BaseItemDto,
        userSession: UserSession
    ) async -> BaseItemDto? {
        switch item.type {
        case .series:
            return item

        case .episode:
            let episode: BaseItemDto

            if seriesID(for: item) != nil {
                episode = item
            } else if let fullItem = try? await item.getFullItem(userSession: userSession) {
                episode = fullItem
            } else {
                return nil
            }

            guard let seriesID = seriesID(for: episode) else { return nil }

            var seriesItem = episode
            seriesItem.id = seriesID
            seriesItem.name = episode.seriesName
            seriesItem.providerIDs = nil
            seriesItem.type = .series
            return seriesItem

        default:
            return nil
        }
    }

    private static func seriesID(for episode: BaseItemDto) -> String? {
        episode.seriesID ?? episode.parentLogoItemID ?? episode.parentBackdropItemID
    }

    private static func getUpcomingEpisode(
        seriesID: String?,
        userSession: UserSession
    ) async -> BaseItemDto? {
        guard let seriesID else { return nil }

        let now = Date()

        var parameters = Paths.GetItemsParameters()
        parameters.enableTotalRecordCount = false
        parameters.fields = .MinimumFields
        parameters.includeItemTypes = [.episode]
        parameters.isRecursive = true
        parameters.limit = 1
        parameters.minPremiereDate = now
        parameters.parentID = seriesID
        parameters.sortBy = [.premiereDate]
        parameters.sortOrder = [.ascending]

        do {
            let response = try await userSession.client.send(Paths.getItems(parameters: parameters))
            return response.value.items?.first(where: { episode in
                episode.premiereDate.map { $0 > now } == true
            })
        } catch {
            return nil
        }
    }
}

extension Date {

    var upcomingEpisodePillLabel: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")

        return L10n.newEpisodeOn(formatter.string(from: self))
    }
}
