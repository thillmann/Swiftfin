//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import Get
import JellyfinAPI
import OrderedCollections
import UIKit

enum ItemDownloadActionAvailability: Equatable {
    case unavailable
    case pending
    case available
}

// TODO: come up with a cleaner, more defined way for item update notifications

class ItemViewModel: ViewModel, PlatformStateful {

    static let mediaSourceCatalogueRequestTimeout: TimeInterval = 60

    /// Non-nil when this model is presenting a completed, package-local item.
    /// Offline models never hydrate or refresh through Jellyfin.
    let offlineRecord: DownloadRecord?

    var isOffline: Bool {
        offlineRecord != nil
    }

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
                let isSamePlaybackItem = playButtonItem?.id == newValue.id
                selectedMediaSource = isSamePlaybackItem
                    ? preservedMediaSourceSelection(
                        in: newValue.mediaSources ?? [],
                        currentSelection: selectedMediaSource
                    )
                    : Self.automaticallySelectedPlaybackSource(
                        in: newValue.mediaSources ?? []
                    )

                if !isSamePlaybackItem {
                    mediaSourceSelectionOrigin = .automatic
                    versionSourcesItemID = nil
                    playbackMediaSourcesTask?.task.cancel()
                }
            }
        }
        didSet {
            #if os(tvOS)
            if playButtonItem?.mediaSources?.isEmpty != false {
                Task { @MainActor [weak self] in
                    await self?.loadPlaybackMediaSources()
                }
            }
            #else
            hydrateMediaSourcesIfNeeded(for: playButtonItem)
            #endif
        }
    }

    @Published
    private(set) var selectedMediaSource: MediaSourceInfo?
    @Published
    private(set) var mediaSourceSelectionOrigin: MediaSourceSelectionOrigin = .automatic
    @Published
    private(set) var isLoadingPlaybackMediaSources = false
    @Published
    private(set) var versionSourcesItemID: String?
    @Published
    var mediaSourceSelectionError: Error?
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

    private var sharedItemEntry: ItemEntry?

    private var toggleIsFavoriteTask: AnyCancellable?
    private var toggleIsPlayedTask: AnyCancellable?
    private var refreshTask: AnyCancellable?
    private var playbackMediaSourcesTask: (itemID: String, task: Task<Void, Never>)?
    #if !os(tvOS)
    private var mediaSourcesTask: AnyCancellable?
    private var hydratedMediaSourceItemIDs: Set<String> = []
    @Published
    private var loadingMediaSourceItemID: String?
    #endif

    // MARK: Media Source Selection

    var mediaSourceSelectionIntent: MediaSourceSelectionIntent {
        if mediaSourceSelectionOrigin == .userSelected, let selectedMediaSource {
            return .userSelected(selectedMediaSource)
        }
        return .automatic
    }

    var playbackMediaSource: MediaSourceInfo? {
        guard let playButtonItem else { return selectedMediaSource }

        return MediaSourceSelection.resolve(
            intent: mediaSourceSelectionIntent,
            candidates: playButtonItem.mediaSources ?? [],
            policy: .balancedPlayback
        )?.selected
    }

    var canDownloadMediaSourceSelection: Bool {
        guard let playButtonItem else { return false }

        switch mediaSourceSelectionIntent {
        case let .userSelected(mediaSource):
            return playButtonItem.canBeDownloaded(mediaSource: mediaSource)
        case .automatic:
            let candidates = playButtonItem.mediaSources?.filter {
                $0.id?.isEmpty == false && playButtonItem.canBeDownloaded(mediaSource: $0)
            } ?? []
            return MediaSourceSelection.resolve(
                intent: .automatic,
                candidates: candidates,
                policy: .balancedDownload
            ) != nil
        }
    }

    func presentAutomaticMediaSourceError() {
        let title = playButtonItem?.displayTitle ?? item.displayTitle
        mediaSourceSelectionError = ErrorMessage(
            "No automatic media source for “\(title)” could be found. Playback was not started."
        )
    }

    var downloadActionAvailability: ItemDownloadActionAvailability {
        guard let playButtonItem,
              [.movie, .episode].contains(playButtonItem.type)
        else {
            return .unavailable
        }

        if hasDownloadTaskOrPreparation {
            return .available
        }

        guard Container.shared.currentUserSession()?.user.data.policy?.enableContentDownloading == true else {
            return .unavailable
        }

        if canDownloadMediaSourceSelection {
            return .available
        }

        #if os(tvOS)
        return isLoadingPlaybackMediaSources ? .pending : .unavailable
        #else
        guard let itemID = playButtonItem.id else { return .unavailable }

        let isPending = loadingMediaSourceItemID == itemID
            || (!hydratedMediaSourceItemIDs.contains(itemID) && shouldHydrateMediaSources(for: playButtonItem))
        return isPending ? .pending : .unavailable
        #endif
    }

    private var hasDownloadTaskOrPreparation: Bool {
        guard let playButtonItem else { return false }

        let downloadManager = Container.shared.downloadManager()
        return downloadManager.task(for: playButtonItem) != nil
            || downloadManager.isPreparingAutomaticDownload(for: playButtonItem)
    }

    // MARK: init

    @MainActor
    init(item: BaseItemDto) {
        self.offlineRecord = nil
        self.item = item
        if item.isPlayable {
            self.playButtonItem = item
            self.selectedMediaSource = Self.automaticallySelectedPlaybackSource(
                in: item.mediaSources ?? []
            )
        }
        super.init()

        observeMetadataChanges()
    }

    @MainActor
    init(item _: BaseItemDto, offlineRecord: DownloadRecord) {
        self.offlineRecord = offlineRecord

        var presentedItem = offlineRecord.item
        presentedItem.mediaSourceCount = 1
        presentedItem.mediaSources = [offlineRecord.mediaSource]
        if let progress = offlineRecord.offlineProgress {
            if presentedItem.userData == nil {
                presentedItem.userData = UserItemDataDto(key: presentedItem.id ?? offlineRecord.presentationItemID)
            }
            presentedItem.userData?.playbackPositionTicks = progress.positionTicks
            presentedItem.userData?.isPlayed = progress.isPlayed
        }

        self.item = presentedItem
        if presentedItem.isPlayable {
            self.playButtonItem = presentedItem
            self.selectedMediaSource = offlineRecord.mediaSource
            self.mediaSourceSelectionOrigin = .userSelected
        }
        super.init()
        state = .content
    }

    private func observeMetadataChanges() {

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

    /// Resolves artwork from the local package in offline mode. A missing
    /// packaged image deliberately produces an empty source instead of falling
    /// back to a Jellyfin URL.
    func imageSource(
        _ type: ImageType,
        index: Int? = nil,
        maxWidth: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        quality: Int? = nil,
        tag: String? = nil
    ) -> ImageSource {
        guard let offlineRecord else {
            return item.imageSource(
                type,
                index: index,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                quality: quality,
                tag: tag
            )
        }

        return ImageSource(
            url: DownloadStorage.imageURL(for: offlineRecord, type: type),
            blurHash: item.blurHashString(for: type),
            trimsTransparentPixels: type == .logo
        )
    }

    // MARK: respond

    func respond(to action: Action) -> State {
        if isOffline {
            if case let .selectMediaSource(source) = action,
               source == offlineRecord?.mediaSource
            {
                selectedMediaSource = source
                mediaSourceSelectionOrigin = .userSelected
            }
            return .content
        }

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
                        self.registerLoadedMediaSources(in: fullItem)

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
                        self.send(.error(.init(error)))
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
                        let fullItem = self.preservingKnownMediaSources(in: results.fullItem)
                        self.registerLoadedMediaSources(in: fullItem)
                        self.item = fullItem
                        self.similarItems = results.similarItems
                        self.specialFeatures = results.specialFeatures
                        self.localTrailers = results.localTrailers
                        self.additionalParts = results.additionalParts

                        self.state = .content
                    }
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.send(.error(.init(error)))
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
            mediaSourceSelectionOrigin = .userSelected

            return state
        }
    }

    private func getFullItem() async throws -> BaseItemDto {
        let requestedItemID = try itemID
        guard let userSession = Container.shared.currentUserSession() else {
            throw ErrorMessage(L10n.unknownError)
        }

        let entry = try await userSession.getFullItem(id: requestedItemID, requestTimeout: Self.mediaSourceCatalogueRequestTimeout)
        sharedItemEntry = entry
        guard let item = entry.value else { throw ItemStore.StoreError.itemUnavailable }

        Notifications[.itemMetadataDidChange].post(item)

        return item
    }

    @MainActor
    private func registerLoadedMediaSources(in loadedItem: BaseItemDto) {
        guard loadedItem.isPlayable, let loadedItemID = loadedItem.id else { return }

        #if !os(tvOS)
        hydratedMediaSourceItemIDs.insert(loadedItemID)
        #endif

        if loadedItem.mediaSources != nil {
            versionSourcesItemID = loadedItemID
        }
    }

    private func preservingKnownMediaSources(in newItem: BaseItemDto) -> BaseItemDto {
        #if os(tvOS)
        return newItem
        #else
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
        #endif
    }

    #if !os(tvOS)
    private func hydrateMediaSourcesIfNeeded(for item: BaseItemDto?) {
        guard !isOffline,
              let item,
              item.isPlayable,
              shouldHydrateMediaSources(for: item),
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

            await self.loadPlaybackMediaSources()
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.loadingMediaSourceItemID = nil
                self.hydratedMediaSourceItemIDs.insert(itemID)
            }
        }
        .asAnyCancellable()
    }

    /// Download records deliberately keep only the selected source. An
    /// interrupted download can leave that reduced item snapshot in navigation
    /// or view caches even after its record is removed, so a single source is
    /// not sufficient evidence that an online item's source list is complete.
    private func shouldHydrateMediaSources(for item: BaseItemDto) -> Bool {
        let loadedSourceCount = item.mediaSources?.count ?? 0
        let advertisedSourceCount = item.mediaSourceCount ?? loadedSourceCount

        return loadedSourceCount <= 1 || advertisedSourceCount > loadedSourceCount
    }

    #endif

    private func matchingMediaSource(
        in mediaSources: [MediaSourceInfo],
        currentSelection: MediaSourceInfo?
    ) -> MediaSourceInfo? {
        guard let currentSelection else { return nil }

        // Some servers use the parent item ID for every version. Prefer the
        // ETag, which remains the unique selection key in that response shape.
        if let currentETag = currentSelection.eTag?.nilIfBlank {
            let matchingETags = mediaSources.filter { $0.eTag?.nilIfBlank == currentETag }
            if matchingETags.count == 1 {
                return matchingETags[0]
            }

            if let exactMatch = matchingETags.first(where: { $0 == currentSelection }) {
                return exactMatch
            }
        }

        if let currentID = currentSelection.id?.nilIfBlank {
            let matchingIDs = mediaSources.filter { $0.id?.nilIfBlank == currentID }
            if matchingIDs.count == 1 {
                return matchingIDs[0]
            }

            if let exactMatch = matchingIDs.first(where: { $0 == currentSelection }) {
                return exactMatch
            }
        }

        return mediaSources.first { $0 == currentSelection }
    }

    private func preservedMediaSourceSelection(
        in mediaSources: [MediaSourceInfo],
        currentSelection: MediaSourceInfo?
    ) -> MediaSourceInfo? {
        if mediaSourceSelectionOrigin == .userSelected {
            return matchingMediaSource(in: mediaSources, currentSelection: currentSelection)
                ?? currentSelection
        }
        return Self.automaticallySelectedPlaybackSource(in: mediaSources)
    }

    private static func automaticallySelectedPlaybackSource(
        in mediaSources: [MediaSourceInfo]
    ) -> MediaSourceInfo? {
        MediaSourceSelection.resolve(
            intent: .automatic,
            candidates: mediaSources,
            policy: .balancedPlayback
        )?.selected
    }

    /// Load the complete item source catalogue. Gelato exposes every version
    /// through the item-detail DTO while PlaybackInfo resolves only one source.
    @MainActor
    func loadPlaybackMediaSources() async {
        guard !isOffline,
              let playbackItem = playButtonItem,
              let playbackItemID = playbackItem.id,
              let userSession = Container.shared.currentUserSession()
        else {
            return
        }

        if let inFlightTask = playbackMediaSourcesTask {
            if inFlightTask.itemID == playbackItemID {
                await inFlightTask.task.value
                return
            }

            inFlightTask.task.cancel()
            await inFlightTask.task.value
            playbackMediaSourcesTask = nil
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            await self.performPlaybackMediaSourcesLoad(
                playbackItemID: playbackItemID,
                userSession: userSession
            )
        }
        playbackMediaSourcesTask = (playbackItemID, task)
        await task.value
        if playbackMediaSourcesTask?.itemID == playbackItemID {
            playbackMediaSourcesTask = nil
        }
    }

    /// Wait for an item-change catalogue request that is already running.
    /// UI actions must not start a second request merely to consume versions.
    @MainActor
    func waitForMediaSourceCatalogue() async {
        guard let playbackItemID = playButtonItem?.id,
              let inFlightTask = playbackMediaSourcesTask,
              inFlightTask.itemID == playbackItemID
        else {
            return
        }

        await inFlightTask.task.value
    }

    @MainActor
    private func performPlaybackMediaSourcesLoad(
        playbackItemID: String,
        userSession: UserSession
    ) async {
        isLoadingPlaybackMediaSources = true
        defer { isLoadingPlaybackMediaSources = false }

        do {
            let response = try await userSession.client.send(
                Paths.getItem(
                    itemID: playbackItemID,
                    userID: userSession.user.id
                ),
                configure: { request in
                    request.timeoutInterval = Self.mediaSourceCatalogueRequestTimeout
                }
            )

            guard !Task.isCancelled,
                  playButtonItem?.id == playbackItemID,
                  let mediaSources = response.value.mediaSources
            else {
                return
            }

            applyPlaybackMediaSources(
                mediaSources,
                for: playbackItemID
            )
            versionSourcesItemID = playbackItemID
        } catch {
            logger.warning(
                "Media source catalogue request failed for item \(playbackItemID): \(error.localizedDescription)"
            )
            return
        }
    }

    private func applyPlaybackMediaSources(
        _ rawMediaSources: [MediaSourceInfo],
        for playbackItemID: String
    ) {
        let mediaSources = Self.uniqueVersionSources(rawMediaSources)
        let currentSelection = selectedMediaSource

        if item.id == playbackItemID {
            var updatedItem = item
            updatedItem.mediaSourceCount = mediaSources.count
            updatedItem.mediaSources = mediaSources
            item = updatedItem
        }

        guard let playbackItem = playButtonItem,
              playbackItem.id == playbackItemID
        else {
            return
        }

        var updatedPlaybackItem = playbackItem
        updatedPlaybackItem.mediaSourceCount = mediaSources.count
        updatedPlaybackItem.mediaSources = mediaSources
        playButtonItem = updatedPlaybackItem
        selectedMediaSource = preservedMediaSourceSelection(
            in: mediaSources,
            currentSelection: currentSelection
        )
    }

    private static func uniqueVersionSources(
        _ mediaSources: [MediaSourceInfo]
    ) -> [MediaSourceInfo] {
        var seenIdentities: Set<String> = []

        return mediaSources.filter { source in
            let identity: String = if let eTag = source.eTag?.nilIfBlank {
                "etag:\(eTag)"
            } else {
                [
                    source.id,
                    source.path,
                    source.name,
                    source.container,
                    source.size.map { String($0) },
                ]
                    .compactMap { $0?.nilIfBlank }
                    .joined(separator: "|")
            }

            guard identity.isNotEmpty else { return true }

            return seenIdentities.insert(identity).inserted
        }
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
        let session = try requireUserSession()
        let entry = try ItemEntry(item: session.items.record(for: item))
        sharedItemEntry = entry
        try await session.setPlayed(entry, to: isPlayed)
        if let value = entry.value { Notifications[.itemMetadataDidChange].post(value) }
    }

    private func setIsFavorite(_ isFavorite: Bool) async throws {
        let session = try requireUserSession()
        let entry = try ItemEntry(item: session.items.record(for: item))
        sharedItemEntry = entry
        try await session.setFavorite(entry, to: isFavorite)
        if let value = entry.value { Notifications[.itemMetadataDidChange].post(value) }
    }
}
