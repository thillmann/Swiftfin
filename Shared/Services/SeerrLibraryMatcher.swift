//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

@MainActor
enum SeerrLibraryMatcher {

    static func libraryMatch(
        for result: SeerrClient.MediaResult,
        using viewModel: ViewModel
    ) async throws -> BaseItemDto? {
        guard let itemType = jellyfinItemType(for: result) else { return nil }
        guard let title = result.title ?? result.name else { return nil }

        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.includeItemTypes = [itemType]
        parameters.isRecursive = true
        parameters.limit = 10
        parameters.searchTerm = title

        let request = Paths.getItems(parameters: parameters)
        let response = try await viewModel.send(request)
        let seerrSignature = mediaSignature(for: result)

        return response.value.items?.first { item in
            mediaSignature(for: item) == seerrSignature
        }
    }

    static func mediaSignature(for jellyfinItem: BaseItemDto) -> String {
        let normalizedTitle = normalizedTitle(jellyfinItem.displayTitle)
        let year = jellyfinItem.productionYear ?? Int(jellyfinItem.premiereDateYear ?? "")

        return "\(normalizedTitle)-\(year ?? 0)"
    }

    static func mediaSignature(for seerrItem: SeerrClient.MediaResult) -> String {
        let normalizedTitle = normalizedTitle(seerrItem.title ?? seerrItem.name ?? "")
        let year = Int((seerrItem.releaseDate ?? seerrItem.firstAirDate ?? "").prefix(4))

        return "\(normalizedTitle)-\(year ?? 0)"
    }

    static func key(for item: SeerrClient.MediaResult) -> String {
        "\(item.mediaType?.rawValue ?? "unknown")-\(item.id)"
    }

    static func updatingRequestStatus(
        in items: [SeerrClient.MediaResult],
        for requestedItem: SeerrClient.MediaResult,
        to status: SeerrClient.MediaStatus
    ) -> [SeerrClient.MediaResult] {
        items.map { item in
            guard item.id == requestedItem.id, item.mediaType == requestedItem.mediaType else { return item }
            return item.updatingStatus(status)
        }
    }

    static func unifiedResults(
        for results: [SeerrClient.MediaResult],
        using viewModel: ViewModel
    ) async -> [UnifiedMediaResult] {
        var unifiedItems: [UnifiedMediaResult] = []

        for result in results {
            if let match = await libraryMatchIgnoringErrors(for: result, using: viewModel) {
                unifiedItems.append(.jellyfin(match))
            } else {
                unifiedItems.append(.seerr(result))
            }
        }

        return unifiedItems
    }

    static func jellyfinItemType(for item: SeerrClient.MediaResult) -> BaseItemKind? {
        switch item.mediaType {
        case .movie:
            .movie
        case .tv:
            .series
        case .person, nil:
            nil
        }
    }

    private static func libraryMatchIgnoringErrors(
        for result: SeerrClient.MediaResult,
        using viewModel: ViewModel
    ) async -> BaseItemDto? {
        do {
            return try await libraryMatch(for: result, using: viewModel)
        } catch {
            return nil
        }
    }

    private static func normalizedTitle(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
