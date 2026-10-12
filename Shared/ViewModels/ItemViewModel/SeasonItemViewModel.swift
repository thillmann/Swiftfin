//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

// Since we don't view care to view seasons directly, this doesn't subclass from `ItemViewModel`.
// If we ever care for viewing seasons directly, subclass from that and have the library view model
// as a property.
final class SeasonItemViewModel: PlatformPagingLibraryViewModel<BaseItemDto>, Identifiable {

    let season: BaseItemDto

    var id: String? {
        season.id
    }

    init(season: BaseItemDto) {
        self.season = season
        super.init(parent: season)
    }

    override func get(page: Int) async throws -> [BaseItemDto] {
        guard let parentID = parent?.id else { return [] }

        let seriesID = season.seriesID ?? season.parentID ?? parentID

        var parameters = Paths.GetEpisodesParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        let shouldShowMissingEpisodes = try authenticatedUser.data.configuration?.isDisplayMissingEpisodes == true
        parameters.isMissing = shouldShowMissingEpisodes ? nil : false
        parameters.seasonID = parentID

        // Episode selectors expect each season to load as a complete contiguous group.

        var request = Paths.getEpisodes(
            seriesID: seriesID,
            parameters: parameters
        )
        var response = try await send(request)

        // As with seasons, provider-backed episodes may be virtual while
        // remaining playable. Only broaden the query when filtering them
        // would otherwise leave the episode rail empty.
        if response.value.items?.isEmpty != false, !shouldShowMissingEpisodes {
            parameters.isMissing = nil
            request = Paths.getEpisodes(seriesID: seriesID, parameters: parameters)
            response = try await send(request)
        }

        return response.value.items ?? []
    }
}
