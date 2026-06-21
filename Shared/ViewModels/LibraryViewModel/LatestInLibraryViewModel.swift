//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

final class LatestInLibraryViewModel: PagingLibraryViewModel<BaseItemDto>, Identifiable {

    #if os(tvOS)
    override var retainsItemsOnRefresh: Bool {
        true
    }
    #endif

    override func get(page: Int) async throws -> [BaseItemDto] {

        let parameters = try parameters(user: authenticatedUser)
        let request = Paths.getLatestMedia(parameters: parameters)
        let response = try await send(request)

        #if os(tvOS)
        if parent?.supportedItemTypes == [.series] {
            return try await seriesItems(for: response.value)
        }
        #endif

        return response.value
    }

    #if os(tvOS)
    private func seriesItems(for latestItems: [BaseItemDto]) async throws -> [BaseItemDto] {

        var seenSeriesIDs: Set<String> = []
        let seriesIDs = latestItems
            .compactMap { item in
                item.type == .series ? item.id : item.seriesID
            }
            .filter { seenSeriesIDs.insert($0).inserted }

        guard seriesIDs.isNotEmpty else { return [] }

        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.ids = seriesIDs
        parameters.includeItemTypes = [.series]
        parameters.limit = seriesIDs.count

        let request = Paths.getItems(parameters: parameters)
        let response = try await send(request)
        let itemsByID = Dictionary(
            (response.value.items ?? []).compactMap { item in
                item.id.map { ($0, item) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        return seriesIDs.compactMap { itemsByID[$0] }
    }
    #endif

    private func parameters(user: UserState) -> Paths.GetLatestMediaParameters {

        var parameters = Paths.GetLatestMediaParameters()
        parameters.parentID = parent?.id
        parameters.fields = .MinimumFields
        parameters.enableUserData = true
        parameters.limit = pageSize

        #if os(tvOS)
        parameters.isGroupItems = parent?.supportedItemTypes == [.series]
        #endif

        if user.data.configuration?.isHidePlayedInLatest == true {
            parameters.isPlayed = false
        }

        return parameters
    }
}
