//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI
import OrderedCollections

@MainActor
@Stateful
final class MediaViewModel: ViewModel {

    @CasePathable
    enum Action {
        case refresh

        var transition: Transition {
            .loop(.refreshing)
        }
    }

    enum State {
        case error
        case initial
        case refreshing
    }

    @Published
    private(set) var mediaItems: OrderedSet<MediaType> = []

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {

        mediaItems.removeAll()

        var media: [MediaType] = try await getUserViews()
            .compactMap { userView in
                if userView.collectionType == .livetv {
                    return .liveTV(userView)
                }

                return .collectionFolder(userView)
            }
            .prepending(.favorites, if: Defaults[.Customization.Library.showFavorites])

        #if os(tvOS)
        if SeerrIntegration.isAvailable {
            media.append(.trending)
        }
        #endif

        mediaItems.elements = media
    }

    private func getUserViews() async throws -> [BaseItemDto] {

        let client = try authenticatedClient
        let parameters = try Paths.GetUserViewsParameters(userID: authenticatedUser.id)
        let userViewsPath = Paths.getUserViews(parameters: parameters)
        async let userViews = client.send(userViewsPath)

        async let excludedLibraryIDs = getExcludedLibraries()

        // folders has `type = UserView`, but we manually
        // force it to `folders` for better view handling
        return try await (userViews.value.items ?? [])
            .coalesced(property: \.collectionType, with: .folders)
            .intersecting(CollectionType.supportedCases, using: \.collectionType)
            .subtracting(excludedLibraryIDs, using: \.id)
            .map { item in

                if item.type == .userView, item.collectionType == .folders {
                    return item.mutating(\.type, with: .folder)
                }

                return item
            }
    }

    private func getExcludedLibraries() async throws -> [String] {
        let currentUserPath = Paths.getCurrentUser
        let response = try await send(currentUserPath)

        return response.value.configuration?.myMediaExcludes ?? []
    }

    func randomItemImageSources(for mediaType: MediaType) async throws -> [ImageSource] {

        #if os(tvOS)
        switch mediaType {
        case .trending:
            let result = await SeerrClient.discoverTrending(language: "en")
            return try seerrImageSources(from: result)
        case .upcoming:
            async let movies = SeerrClient.discoverUpcomingMovies()
            async let tv = SeerrClient.discoverUpcomingTV()
            let (movieResult, tvResult) = await (movies, tv)

            return try seerrImageSources(from: movieResult) + seerrImageSources(from: tvResult)
        default:
            break
        }
        #endif

        // live tv doesn't have random
        if case MediaType.liveTV = mediaType {
            return []
        }

        // downloads doesn't have random
        if mediaType == .downloads {
            return []
        }

        var parentID: String?

        if case let MediaType.collectionFolder(item) = mediaType {
            parentID = item.id
        }

        var filters: [ItemTrait]?

        if mediaType == .favorites {
            filters = [.isFavorite]
        }

        var parameters = Paths.GetItemsParameters()
        parameters.limit = 3
        parameters.isRecursive = true
        parameters.parentID = parentID
        parameters.includeItemTypes = BaseItemKind.supportedCases
        parameters.filters = filters
        parameters.sortBy = [ItemSortBy.random]

        let request = Paths.getItems(parameters: parameters)
        let response = try await send(request)

        return (response.value.items ?? [])
            .flatMap { $0.landscapeImageSources(maxWidth: 200) }
    }

    #if os(tvOS)
    private func seerrImageSources(
        from result: Result<SeerrClient.Page<SeerrClient.MediaResult>, SeerrClient.ProbeError>
    ) throws -> [ImageSource] {
        switch result {
        case let .success(page):
            return page.results.prefix(2).map(\.backdropImageSource)
        case let .failure(error):
            throw error
        }
    }
    #endif
}
