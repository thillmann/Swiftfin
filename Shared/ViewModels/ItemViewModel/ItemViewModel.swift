//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Factory
import Foundation
import Get
import JellyfinAPI
import OrderedCollections
import UIKit

// TODO: come up with a cleaner, more defined way for item update notifications

class ItemViewModel: ViewModel, Stateful {

    // MARK: Action

    enum Action: Equatable {
        case backgroundRefresh
        case error(ErrorMessage)
        case refresh
        case replace(BaseItemDto)
        case toggleIsFavorite
        case toggleIsPlayed
        case selectMediaSource(MediaSourceInfo)
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

    // TODO: create value on `BaseItemDto` whether an item
    //       only has children as playable items
    @Published
    private(set) var item: BaseItemDto {
        willSet {
            if item.isPlayable {
                playButtonItem = newValue
            }
        }
    }

    @Published
    var playButtonItem: BaseItemDto? {
        willSet {
            if let newValue {
                selectedMediaSource = newValue.mediaSources?.first
            }
        }
        didSet {
            hydrateMediaSourcesIfNeeded(for: playButtonItem)
        }
    }

    @Published
    private(set) var selectedMediaSource: MediaSourceInfo?
    @Published
    private(set) var similarItems: [BaseItemDto] = []
    @Published
    private(set) var specialFeatures: [BaseItemDto] = []
    @Published
    private(set) var localTrailers: [BaseItemDto] = []
    @Published
    private(set) var additionalParts: [BaseItemDto] = []

    @Published
    var backgroundStates: Set<BackgroundState> = []
    @Published
    var state: State = .initial

    private var itemID: String {
        get throws {
            guard let id = item.id else {
                logger.error("Item ID is nil")
                throw ErrorMessage(L10n.unknownError)
            }
            return id
        }
    }

    // tasks

    private var toggleIsFavoriteTask: AnyCancellable?
    private var toggleIsPlayedTask: AnyCancellable?
    private var refreshTask: AnyCancellable?
    private var mediaSourcesTask: AnyCancellable?
    private var hydratedMediaSourceItemIDs: Set<String> = []
    private var loadingMediaSourceItemID: String?

    // MARK: init

    @MainActor
    init(item: BaseItemDto) {
        self.item = item
        if item.isPlayable {
            self.playButtonItem = item
            self.selectedMediaSource = item.mediaSources?.first
        }
        super.init()

        hydrateMediaSourcesIfNeeded(for: playButtonItem)

        Notifications[.itemShouldRefreshMetadata]
            .publisher
            .sink { [weak self] itemID in
                guard itemID == self?.item.id else { return }

                Task {
                    await self?.send(.backgroundRefresh)
                }
            }
            .store(in: &cancellables)

        Notifications[.itemMetadataDidChange]
            .publisher
            .sink { [weak self] newItem in
                guard let newItemID = newItem.id, newItemID == self?.item.id else { return }

                Task {
                    await self?.send(.replace(newItem))
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    convenience init(episode: BaseItemDto) {
        let shellSeriesItem = BaseItemDto(id: episode.seriesID, name: episode.seriesName)
        self.init(item: shellSeriesItem)
    }

    // MARK: respond

    func respond(to action: Action) -> State {
        switch action {
        case .backgroundRefresh:

            backgroundStates.insert(.refresh)

            Task { [weak self] in
                guard let self else { return }
                do {
                    async let fullItem = getFullItem()
                    async let similarItems = getSimilarItems()
                    async let specialFeatures = getSpecialFeatures()
                    async let localTrailers = getLocalTrailers()

                    let results = try await (
                        fullItem: fullItem,
                        similarItems: similarItems,
                        specialFeatures: specialFeatures,
                        localTrailers: localTrailers
                    )

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.backgroundStates.remove(.refresh)
                        let fullItem = self.preservingKnownMediaSources(in: results.fullItem)

                        if fullItem.id != self.item.id || fullItem != self.item {
                            self.item = fullItem
                        }

                        if !results.similarItems.elementsEqual(self.similarItems, by: { $0.id == $1.id }) {
                            self.similarItems = results.similarItems
                        }

                        if !results.specialFeatures.elementsEqual(self.specialFeatures, by: { $0.id == $1.id }) {
                            self.specialFeatures = results.specialFeatures
                        }

                        if !results.localTrailers.elementsEqual(self.localTrailers, by: { $0.id == $1.id }) {
                            self.localTrailers = results.localTrailers
                        }
                    }
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.backgroundStates.remove(.refresh)
                        self.send(.error(.init(error.localizedDescription)))
                    }
                }
            }
            .store(in: &cancellables)

            return state
        case let .error(error):
            return .error(error)
        case .refresh:

            refreshTask?.cancel()

            refreshTask = Task { [weak self] in
                guard let self else { return }
                do {
                    async let fullItem = getFullItem()
                    async let similarItems = getSimilarItems()
                    async let specialFeatures = getSpecialFeatures()
                    async let localTrailers = getLocalTrailers()
                    async let additionalParts = getAdditionalParts()

                    let results = try await (
                        fullItem: fullItem,
                        similarItems: similarItems,
                        specialFeatures: specialFeatures,
                        localTrailers: localTrailers,
                        additionalParts: additionalParts
                    )

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.item = self.preservingKnownMediaSources(in: results.fullItem)
                        self.similarItems = results.similarItems
                        self.specialFeatures = results.specialFeatures
                        self.localTrailers = results.localTrailers
                        self.additionalParts = results.additionalParts

                        self.state = .content
                    }
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.send(.error(.init(error.localizedDescription)))
                    }
                }
            }
            .asAnyCancellable()

            return .refreshing
        case let .replace(newItem):

            backgroundStates.insert(.refresh)

            Task { [weak self] in
                guard let self else { return }
                do {
                    await MainActor.run {
                        self.backgroundStates.remove(.refresh)
                        self.item = self.preservingKnownMediaSources(in: newItem)
                    }
                }
            }
            .store(in: &cancellables)

            return state
        case .toggleIsFavorite:

            toggleIsFavoriteTask?.cancel()

            toggleIsFavoriteTask = Task {

                let beforeIsFavorite = item.userData?.isFavorite ?? false

                await MainActor.run {
                    item.userData?.isFavorite?.toggle()
                }

                do {
                    try await setIsFavorite(!beforeIsFavorite)
                } catch {
                    await MainActor.run {
                        item.userData?.isFavorite = beforeIsFavorite
                        // emit event that toggle unsuccessful
                    }
                }
            }
            .asAnyCancellable()

            return state
        case .toggleIsPlayed:

            toggleIsPlayedTask?.cancel()

            toggleIsPlayedTask = Task {

                let beforeIsPlayed = item.userData?.isPlayed ?? false

                await MainActor.run {
                    item.userData?.isPlayed?.toggle()
                }

                do {
                    try await setIsPlayed(!beforeIsPlayed)
                } catch {
                    await MainActor.run {
                        item.userData?.isPlayed = beforeIsPlayed
                        // emit event that toggle unsuccessful
                    }
                }
            }
            .asAnyCancellable()

            return state
        case let .selectMediaSource(newSource):

            selectedMediaSource = newSource

            return state
        }
    }

    private func getFullItem() async throws -> BaseItemDto {
        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .ItemDetailFields
        parameters.ids = try [itemID]
        parameters.limit = 1

        let request = Paths.getItems(parameters: parameters)
        let response = try await send(request)

        guard let item = response.value.items?.first else {
            throw ErrorMessage(L10n.unknownError)
        }

        Notifications[.itemMetadataDidChange].post(item)

        return item
    }

    private func preservingKnownMediaSources(in newItem: BaseItemDto) -> BaseItemDto {
        guard newItem.mediaSources?.isEmpty != false else { return newItem }

        let knownMediaSources = [
            item.id == newItem.id ? item.mediaSources : nil,
            playButtonItem?.id == newItem.id ? playButtonItem?.mediaSources : nil,
        ]
            .compacted()
            .first { $0.isNotEmpty }

        guard let knownMediaSources else {
            return newItem
        }

        var updatedItem = newItem
        updatedItem.mediaSourceCount = max(
            newItem.mediaSourceCount ?? 0,
            knownMediaSources.count
        )
        updatedItem.mediaSources = knownMediaSources

        return updatedItem
    }

    private func hydrateMediaSourcesIfNeeded(for item: BaseItemDto?) {
        guard let item,
              item.isPlayable,
              item.mediaSources?.isEmpty != false,
              let itemID = item.id,
              loadingMediaSourceItemID != itemID,
              !hydratedMediaSourceItemIDs.contains(itemID)
        else {
            return
        }

        loadingMediaSourceItemID = itemID
        mediaSourcesTask?.cancel()

        mediaSourcesTask = Task { [weak self] in
            guard let self else { return }

            do {
                let sourceItem = try await getMediaSourceItem(itemID: itemID)

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.loadingMediaSourceItemID = nil

                    if sourceItem.mediaSources != nil {
                        self.hydratedMediaSourceItemIDs.insert(itemID)
                        self.applyMediaSources(from: sourceItem, itemID: itemID)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.loadingMediaSourceItemID = nil
                }
            }
        }
        .asAnyCancellable()
    }

    private func getMediaSourceItem(itemID: String) async throws -> BaseItemDto {
        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MediaSourceFields
        parameters.ids = [itemID]
        parameters.limit = 1

        let request = Paths.getItems(parameters: parameters)
        let response = try await send(request)

        guard let item = response.value.items?.first else {
            throw ErrorMessage(L10n.unknownError)
        }

        return item
    }

    private func applyMediaSources(from sourceItem: BaseItemDto, itemID: String) {
        guard let mediaSources = sourceItem.mediaSources else { return }

        let currentSelection = selectedMediaSource

        if item.id == itemID {
            var updatedItem = item
            updatedItem.mediaSourceCount = sourceItem.mediaSourceCount ?? mediaSources.count
            updatedItem.mediaSources = mediaSources
            item = updatedItem
        }

        if playButtonItem?.id == itemID {
            var updatedPlayButtonItem = playButtonItem
            updatedPlayButtonItem?.mediaSourceCount = sourceItem.mediaSourceCount ?? mediaSources.count
            updatedPlayButtonItem?.mediaSources = mediaSources
            playButtonItem = updatedPlayButtonItem
        }

        selectedMediaSource = matchingMediaSource(
            in: mediaSources,
            currentSelection: currentSelection
        ) ?? mediaSources.first
    }

    private func matchingMediaSource(
        in mediaSources: [MediaSourceInfo],
        currentSelection: MediaSourceInfo?
    ) -> MediaSourceInfo? {
        guard let currentSelection else { return nil }

        if let currentID = currentSelection.id,
           let matchingID = mediaSources.first(where: { $0.id == currentID })
        {
            return matchingID
        }

        if let currentETag = currentSelection.eTag,
           let matchingETag = mediaSources.first(where: { $0.eTag == currentETag })
        {
            return matchingETag
        }

        return mediaSources.first { $0 == currentSelection }
    }

    private func getSimilarItems() async throws -> [BaseItemDto] {
        guard let itemID = item.id else { return [] }

        var parameters = Paths.GetSimilarItemsParameters()
        parameters.fields = .MinimumFields
        parameters.limit = 20

        let request = Paths.getSimilarItems(
            itemID: itemID,
            parameters: parameters
        )

        let response = try? await send(request)

        return response?.value.items ?? []
    }

    private func getSpecialFeatures() async throws -> [BaseItemDto] {
        guard let itemID = item.id else { return [] }

        let request = try Paths.getSpecialFeatures(
            itemID: itemID,
            userID: authenticatedUser.id
        )
        let response = try? await send(request)

        return (response?.value ?? [])
            .filter { $0.extraType?.isVideo ?? false }
    }

    private func getLocalTrailers() async throws -> [BaseItemDto] {

        let request = try Paths.getLocalTrailers(itemID: itemID, userID: authenticatedUser.id)
        let response = try? await send(request)

        return response?.value ?? []
    }

    private func getAdditionalParts() async throws -> [BaseItemDto] {

        guard let partCount = item.partCount,
              partCount > 1,
              let itemID = item.id else { return [] }

        let request = Paths.getAdditionalPart(itemID: itemID)
        let response = try? await send(request)

        return response?.value.items ?? []
    }

    private func setIsPlayed(_ isPlayed: Bool) async throws {

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
        Notifications[.itemShouldRefreshMetadata].post(itemID)
    }

    private func setIsFavorite(_ isFavorite: Bool) async throws {

        guard let itemID = item.id else { return }

        let request: Request<UserItemDataDto> = if isFavorite {
            try Paths.markFavoriteItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        } else {
            try Paths.unmarkFavoriteItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        }

        _ = try await send(request)
        Notifications[.itemShouldRefreshMetadata].post(itemID)
    }
}
