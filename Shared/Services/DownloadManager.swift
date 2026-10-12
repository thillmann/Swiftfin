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
import JellyfinAPI
import Logging
import UIKit

extension Container {
    var downloadManager: Factory<DownloadManager> {
        self { DownloadManager() }.singleton
    }
}

/// Persistent, version-aware background download coordinator.
final class DownloadManager: NSObject, ObservableObject {

    struct DownloadSummary: Equatable {
        let totalCount: Int
        let completedCount: Int
        let activeCount: Int
        let resolvingCount: Int
        let pausedCount: Int
        let failedCount: Int
        let progress: Double

        static let empty = DownloadSummary(
            totalCount: 0,
            completedCount: 0,
            activeCount: 0,
            resolvingCount: 0,
            pausedCount: 0,
            failedCount: 0,
            progress: 0
        )

        var hasDownloads: Bool {
            completedCount + activeCount + pausedCount + failedCount > 0
        }

        var isComplete: Bool {
            totalCount > 0 && completedCount == totalCount
        }

        var isActive: Bool {
            activeCount + pausedCount > 0
        }
    }

    enum DownloadError: LocalizedError {
        case invalidItem
        case missingMediaSource
        case unsupportedItem
        case unsupportedDiscMedia
        case unsupportedHLS
        case unsupportedLiveStream
        case unsupportedRemoteOrPluginSource
        case staticProxyFailed
        case invalidUpstreamResponse
        case upstreamHTTPError(Int)
        case upstreamTransportError
        case versionCouldNotBeResolved
        case versionIsNotDownloadable
        case notEnoughStorage
        case invalidResponse
        case missingSession

        var errorDescription: String? {
            switch self {
            case .invalidItem: "The item is missing required download information."

            case .missingMediaSource: "Select a version before downloading."

            case .unsupportedItem: "Only finite movie and episode files can be downloaded."

            case .unsupportedDiscMedia: "DVD and Blu-ray folder sources cannot be downloaded."

            case .unsupportedHLS: "HLS video-on-demand requires a future offline HLS downloader."

            case .unsupportedLiveStream: "Live and infinite streams cannot be downloaded."

            case .unsupportedRemoteOrPluginSource:
                "This source protocol is not supported for offline downloads."

            case .staticProxyFailed:
                "Jellyfin could not provide the selected finite HTTP source as a static media file."

            case .invalidUpstreamResponse:
                "The media provider returned an invalid download."

            case let .upstreamHTTPError(statusCode):
                if (500 ..< 600).contains(statusCode) {
                    "The media provider is temporarily unavailable (HTTP \(statusCode)). Try again later."
                } else {
                    "The media provider returned HTTP \(statusCode)."
                }

            case .upstreamTransportError:
                "The media provider connection failed. Try again later."

            case .versionCouldNotBeResolved:
                "The selected version could not be resolved to its own downloadable Jellyfin item."

            case .versionIsNotDownloadable: "The selected version is not downloadable for this user."

            case .notEnoughStorage: "There is not enough free storage for this download."

            case .invalidResponse: "The server returned an invalid download."

            case .missingSession: "The Jellyfin user session is unavailable."
            }
        }
    }

    private static let persistenceOwner = "swiftfinDownloads"
    private static let persistenceField = "records"
    private static let persistenceKey = "v1"
    private static let backgroundSessionIdentifier = "org.jellyfin.swiftfin.media-downloads"

    /// Set by the app delegate when iOS relaunches the application to deliver
    /// background URLSession events.
    static var backgroundCompletionHandler: (() -> Void)?

    /// Registers the completion callback supplied by UIKit when it relaunches
    /// the app for this download session. Keeping this check here prevents an
    /// unrelated background URLSession from being acknowledged by the
    /// download coordinator.
    @discardableResult
    static func registerBackgroundSessionEvents(
        identifier: String,
        completionHandler: @escaping () -> Void
    ) -> Bool {
        guard identifier == backgroundSessionIdentifier else { return false }

        backgroundCompletionHandler = completionHandler
        return true
    }

    private let logger = Logger.swiftfin()
    private var records: [String: DownloadRecord] = [:]
    private var recordIDsByScope: [ItemDownloadScope: String] = [:]
    private var taskAdapters: [String: DownloadTask] = [:]
    private var taskAdaptersByScope: [ItemDownloadScope: DownloadTask] = [:]
    private var taskAdaptersBySeries: [SeriesDownloadScope: [DownloadTask]] = [:]
    private var backgroundSession: URLSession!
    private var cancellables = Set<AnyCancellable>()
    private var isStorePrepared = false
    private var pendingReplacementScopes = Set<ItemDownloadScope>()
    private var pendingSeriesArtworkSeriesIDs = Set<String>()
    private var downloadBatchDepth = 0
    private var needsRefreshAfterDownloadBatch = false
    private var isProgressPersistenceScheduled = false
    private var isAggregateRefreshScheduled = false
    private var currentDownloadBatchID: String?
    private var pendingPersistenceWorkItem: DispatchWorkItem?
    private var pendingPersistenceRequiresStore = false
    private var pendingPersistenceSnapshot: PersistenceSnapshot?
    private var isPersistenceWriteInFlight = false
    private var persistenceDrainCompletions: [() -> Void] = []
    private var lastProgressPublicationDates: [String: Date] = [:]
    private var pendingResolutions: [PendingResolution] = []
    private var activeResolutionCount = 0
    private var pendingFinalizationRecordIDs: [String] = []
    private var activeFinalizationCount = 0
    private var pendingAutomaticDownloadBatches: [UUID: PendingAutomaticDownloadBatch] = [:]
    private var pendingAutomaticDownloadScopes: Set<ItemDownloadScope> = []

    private let persistenceQueue = DispatchQueue(
        label: "org.jellyfin.swiftfin.download-persistence",
        qos: .utility
    )
    private let fileIOQueue = DispatchQueue(
        label: "org.jellyfin.swiftfin.download-file-io",
        qos: .utility
    )

    private static let maximumConcurrentResolutions = 3
    private static let maximumConcurrentFinalizations = 2
    private static let progressPublicationInterval: TimeInterval = 0.2
    private static let persistenceDebounceInterval: TimeInterval = 0.5
    private static let progressPersistenceInterval: TimeInterval = 5
    private static let minimumComparableMediaSize: Int64 = 10_000_000
    private static let minimumPlausibleMediaFraction: Int64 = 20

    private struct PendingResolution {
        let recordID: String
        let presentationItem: BaseItemDto
        let selectedMediaSource: MediaSourceInfo
        let session: UserSession
        let resolutionStartedAt: Date
    }

    private struct PersistenceSnapshot {
        var values: [DownloadRecord]
        var shouldStore: Bool
    }

    private struct ItemDownloadScope: Hashable {
        let serverID: String
        let userID: String
        let presentationItemID: String

        init(record: DownloadRecord) {
            self.init(
                serverID: record.serverID,
                userID: record.userID,
                presentationItemID: record.presentationItemID
            )
        }

        init(serverID: String, userID: String, presentationItemID: String) {
            self.serverID = serverID
            self.userID = userID
            self.presentationItemID = presentationItemID
        }
    }

    private struct PendingAutomaticDownloadBatch {
        let items: [BaseItemDto]
        var scopes: Set<ItemDownloadScope>
        var task: Task<Void, Never>?
    }

    private struct SeriesDownloadScope: Hashable {
        let serverID: String
        let userID: String
        let seriesID: String
    }

    @Published
    private(set) var downloads: [DownloadTask] = []

    /// Scoped aggregate controls subscribe to this throttled signal without
    /// invalidating every view that observes structural download membership.
    let aggregateUpdates = PassthroughSubject<Void, Never>()

    override init() {
        super.init()

        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.backgroundSessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.allowsCellularAccess = true
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        if #available(iOS 13.0, tvOS 13.0, *) {
            configuration.allowsExpensiveNetworkAccess = true
            configuration.allowsConstrainedNetworkAccess = true
        }

        backgroundSession = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: OperationQueue.main
        )

        loadFileIndex()
        discardCancelledRecords()
        clearPendingDeletionFolders()
        normalizeTransferStrategies()
        if normalizeDuplicateRecords() {
            persist()
        }
        rebuildAdapters()
        reconcileBackgroundTasks()

        Notifications[.applicationWillEnterForeground]
            .publisher
            .sink { [weak self] in
                self?.reconcileBackgroundTasks()
                self?.syncOfflineProgress()
            }
            .store(in: &cancellables)
    }

    /// Called after CoreStore setup. The JSON index and per-download manifests
    /// are recovery mirrors; AnyStoredData is the normal persistent index.
    func prepare() {
        guard !isStorePrepared else { return }

        isStorePrepared = true

        if let stored: [DownloadRecord] = try? AnyStoredData.fetch(
            ownerID: Self.persistenceOwner,
            field: Self.persistenceField,
            key: Self.persistenceKey
        ), stored.isNotEmpty {
            records = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
        }

        discardCancelledRecords()
        normalizeTransferStrategies()
        migrateLegacyDownloadsIfNeeded()
        normalizeDuplicateRecords()
        rebuildAdapters()
        reconcileBackgroundTasks()
        persist()
        syncOfflineProgress()
    }

    // MARK: Queries

    func task(for item: BaseItemDto, mediaSource: MediaSourceInfo? = nil) -> DownloadTask? {
        guard let session = Container.shared.currentUserSession(),
              let itemID = item.id
        else { return nil }

        if let mediaSourceID = mediaSource?.id {
            let id = DownloadRecord.makeID(
                serverID: session.server.id,
                userID: session.user.id,
                itemID: itemID,
                mediaSourceID: mediaSourceID
            )
            guard let task = taskAdapters[id],
                  let record = task.record,
                  isSameSource(record, mediaSource)
            else { return nil }

            return task
        }

        return taskAdaptersByScope[
            ItemDownloadScope(
                serverID: session.server.id,
                userID: session.user.id,
                presentationItemID: itemID
            )
        ]
    }

    func record(for item: BaseItemDto, mediaSource: MediaSourceInfo?) -> DownloadRecord? {
        task(for: item, mediaSource: mediaSource)?.record
    }

    func completedRecord(for item: BaseItemDto, mediaSource: MediaSourceInfo?) -> DownloadRecord? {
        guard let record = record(for: item, mediaSource: mediaSource),
              record.status == .completed,
              let mediaURL = DownloadStorage.mediaURL(for: record),
              FileManager.default.fileExists(atPath: mediaURL.path)
        else { return nil }

        return record
    }

    func downloadedItems() -> [DownloadTask] {
        downloadedItems(from: downloads)
    }

    func downloadedItems(from downloads: [DownloadTask]) -> [DownloadTask] {
        guard let session = Container.shared.currentUserSession() else { return [] }

        let matching = downloads.filter {
            $0.record?.serverID == session.server.id && $0.record?.userID == session.user.id
                && $0.record.map(Self.isVisibleInDownloadLibrary) == true
        }
        let newestByItem = matching.reduce(into: [String: DownloadTask]()) { result, task in
            guard let record = task.record else { return }

            if let existing = result[record.presentationItemID]?.record {
                let isNewer = record.updatedAt > existing.updatedAt
                    || (record.updatedAt == existing.updatedAt && record.id > existing.id)
                guard isNewer else { return }
            }
            result[record.presentationItemID] = task
        }
        return newestByItem.values.sorted {
            ($0.record?.updatedAt ?? .distantPast) > ($1.record?.updatedAt ?? .distantPast)
        }
    }

    func tasks(for items: [BaseItemDto]) -> [DownloadTask] {
        guard let session = Container.shared.currentUserSession() else { return [] }

        return items.compactMap { item in
            guard let itemID = item.id,
                  let recordID = recordIDsByScope[
                      ItemDownloadScope(
                          serverID: session.server.id,
                          userID: session.user.id,
                          presentationItemID: itemID
                      )
                  ]
            else { return nil }

            return taskAdapters[recordID]
        }
    }

    func tasks(forSeriesID seriesID: String, seasonNumber: Int? = nil) -> [DownloadTask] {
        guard let session = Container.shared.currentUserSession() else { return [] }

        let matching = taskAdaptersBySeries[
            SeriesDownloadScope(
                serverID: session.server.id,
                userID: session.user.id,
                seriesID: seriesID
            )
        ] ?? []
        guard let seasonNumber else { return matching }

        return matching.filter { $0.item.parentIndexNumber == seasonNumber }
    }

    func isPreparingAutomaticDownload(for item: BaseItemDto) -> Bool {
        guard let scope = downloadScope(for: item) else { return false }

        return pendingAutomaticDownloadScopes.contains(scope)
    }

    /// Produces a stable aggregate over a known episode set. Completed records
    /// remain in the set, preventing the ring from moving backwards as each
    /// transfer finishes. Bytes are used when every item has an expected size;
    /// otherwise each episode contributes an equal share.
    func summary(for items: [BaseItemDto]) -> DownloadSummary {
        let matchingTasks = tasks(for: items)
        let hasPendingPreparation = items.contains(where: isPreparingAutomaticDownload(for:))
        let activeBatchIDs = Set(matchingTasks.compactMap { task -> String? in
            guard task.state.isInProgress else { return nil }

            return task.record?.batchID
        })
        let scopedTasks = activeBatchIDs.isEmpty ? matchingTasks : matchingTasks.filter {
            $0.record?.batchID.map(activeBatchIDs.contains) == true
        }
        let summaryTasks = hasPendingPreparation ? matchingTasks : scopedTasks
        let taskByItemID = Dictionary(
            summaryTasks.compactMap { task in
                task.record.map { ($0.presentationItemID, task) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let scopedItems = activeBatchIDs.isEmpty || hasPendingPreparation ? items : scopedTasks.map(\.item)
        return makeSummary(items: scopedItems, tasksByItemID: taskByItemID)
    }

    /// Aggregate used before a season's episode metadata has been loaded and
    /// by the show toolbar. Its scope is the persisted records for that show.
    func summary(
        forSeriesID seriesID: String,
        seasonNumber: Int? = nil,
        expectedTotalCount: Int? = nil
    ) -> DownloadSummary {
        let matching = tasks(forSeriesID: seriesID, seasonNumber: seasonNumber)
        let pendingItems = pendingAutomaticDownloadItems(
            forSeriesID: seriesID,
            seasonNumber: seasonNumber
        )
        let hasPendingPreparation = pendingItems.isNotEmpty
        let activeBatchIDs = Set(matching.compactMap { task -> String? in
            guard task.state.isInProgress else { return nil }

            return task.record?.batchID
        })
        let scopedTasks = activeBatchIDs.isEmpty ? matching : matching.filter {
            $0.record?.batchID.map(activeBatchIDs.contains) == true
        }
        let summaryTasks = hasPendingPreparation ? matching : scopedTasks
        let taskByItemID = Dictionary(
            summaryTasks.compactMap { task in
                task.record.map { ($0.presentationItemID, task) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        var summaryItems = activeBatchIDs.isEmpty || hasPendingPreparation ? matching.map(\.item) : scopedTasks.map(\.item)
        let knownItemIDs = Set(summaryItems.compactMap(\.id))
        summaryItems.append(contentsOf: pendingItems.filter { item in
            item.id.map { !knownItemIDs.contains($0) } ?? false
        })
        let summary = makeSummary(items: summaryItems, tasksByItemID: taskByItemID)
        guard activeBatchIDs.isEmpty || hasPendingPreparation,
              let expectedTotalCount,
              expectedTotalCount > summary.totalCount
        else { return summary }

        return DownloadSummary(
            totalCount: expectedTotalCount,
            completedCount: summary.completedCount,
            activeCount: summary.activeCount,
            resolvingCount: summary.resolvingCount,
            pausedCount: summary.pausedCount,
            failedCount: summary.failedCount,
            progress: summary.progress * Double(summary.totalCount) / Double(expectedTotalCount)
        )
    }

    func cancelDownloads(for items: [BaseItemDto]) {
        cancelPendingAutomaticDownloads(for: Set(items.compactMap(downloadScope(for:))))
        let matchingTasks = tasks(for: items)
        let activeRecords = matchingTasks
            .filter(\.state.isInProgress)
            .compactMap(\.record)
        let activeRecordIDs = Set(activeRecords.map(\.id))
        let activeBatchIDs = Set(activeRecords.compactMap(\.batchID))
        let candidates = matchingTasks
            .compactMap(\.record)
            .filter { record in
                record.status != .completed
                    && (activeRecordIDs.contains(record.id)
                        || record.batchID.map(activeBatchIDs.contains) == true)
            }
            .filter { records[$0.id]?.createdAt == $0.createdAt }
        discardRecords(candidates)
    }

    func removeDownloads(for items: [BaseItemDto]) {
        cancelPendingAutomaticDownloads(for: Set(items.compactMap(downloadScope(for:))))
        let candidates = tasks(for: items)
            .compactMap(\.record)
            .filter { records[$0.id]?.createdAt == $0.createdAt }
        discardRecords(candidates)
    }

    private func downloadScope(for item: BaseItemDto) -> ItemDownloadScope? {
        guard let session = Container.shared.currentUserSession(), let itemID = item.id else { return nil }

        return ItemDownloadScope(
            serverID: session.server.id,
            userID: session.user.id,
            presentationItemID: itemID
        )
    }

    private func pendingAutomaticDownloadItems(
        forSeriesID seriesID: String,
        seasonNumber: Int?
    ) -> [BaseItemDto] {
        guard let session = Container.shared.currentUserSession() else { return [] }

        return pendingAutomaticDownloadBatches.values
            .flatMap { batch in
                batch.items.filter { item in
                    guard item.seriesID == seriesID,
                          let itemID = item.id,
                          seasonNumber == nil || item.parentIndexNumber == seasonNumber
                    else { return false }

                    return batch.scopes.contains(
                        ItemDownloadScope(
                            serverID: session.server.id,
                            userID: session.user.id,
                            presentationItemID: itemID
                        )
                    )
                }
            }
    }

    private func finishPendingAutomaticDownloadBatch(_ batchID: UUID) {
        guard pendingAutomaticDownloadBatches.removeValue(forKey: batchID) != nil else { return }

        refreshPendingAutomaticDownloadScopes()
        publishPendingAutomaticDownloadChange()
    }

    private func finishPendingAutomaticDownloadScope(
        _ scope: ItemDownloadScope,
        in batchID: UUID
    ) {
        guard var batch = pendingAutomaticDownloadBatches[batchID] else { return }

        batch.scopes.remove(scope)
        pendingAutomaticDownloadBatches[batchID] = batch
        refreshPendingAutomaticDownloadScopes()
        publishPendingAutomaticDownloadChange()
    }

    private func cancelPendingAutomaticDownloads(for scopes: Set<ItemDownloadScope>) {
        guard scopes.isNotEmpty else { return }

        let matchingBatchIDs = pendingAutomaticDownloadBatches.compactMap { batchID, batch in
            batch.scopes.isDisjoint(with: scopes) ? nil : batchID
        }
        guard matchingBatchIDs.isNotEmpty else { return }

        for batchID in matchingBatchIDs {
            guard var batch = pendingAutomaticDownloadBatches[batchID] else { continue }

            batch.scopes.subtract(scopes)
            if batch.scopes.isEmpty {
                pendingAutomaticDownloadBatches.removeValue(forKey: batchID)?.task?.cancel()
            } else {
                pendingAutomaticDownloadBatches[batchID] = batch
            }
        }
        refreshPendingAutomaticDownloadScopes()
        publishPendingAutomaticDownloadChange()
    }

    private func refreshPendingAutomaticDownloadScopes() {
        pendingAutomaticDownloadScopes = pendingAutomaticDownloadBatches.values.reduce(into: []) {
            $0.formUnion($1.scopes)
        }
    }

    private func publishPendingAutomaticDownloadChange() {
        objectWillChange.send()
        aggregateUpdates.send()
    }

    private func makeSummary(
        items: [BaseItemDto],
        tasksByItemID: [String: DownloadTask]
    ) -> DownloadSummary {
        guard items.isNotEmpty else { return .empty }

        var completedCount = 0
        var activeCount = 0
        var resolvingCount = 0
        var pausedCount = 0
        var failedCount = 0
        var episodeProgress: [Double] = []
        var byteProgress: [(progress: Double, expectedBytes: Double)] = []
        var hasExpectedBytesForEveryItem = true

        for item in items {
            let task = item.id.flatMap { tasksByItemID[$0] }
            let progress: Double
            if task == nil, isPreparingAutomaticDownload(for: item) {
                activeCount += 1
                resolvingCount += 1
                progress = 0
            } else {
                switch task?.state {
                case .complete:
                    completedCount += 1
                    progress = 1

                case .downloading:
                    activeCount += 1
                    progress = task?.transferProgress ?? 0

                case .resolving:
                    activeCount += 1
                    resolvingCount += 1
                    progress = task?.transferProgress ?? 0

                case .paused:
                    pausedCount += 1
                    progress = task?.transferProgress ?? 0

                case .error:
                    failedCount += 1
                    progress = task?.transferProgress ?? 0

                case .cancelled, .ready, nil:
                    progress = 0
                }
            }
            episodeProgress.append(progress)

            let expectedBytes = task?.record?.expectedBytes
                ?? item.mediaSources?.first?.size.map(Int64.init)
            if let expectedBytes, expectedBytes > 0 {
                byteProgress.append((progress, Double(expectedBytes)))
            } else {
                hasExpectedBytesForEveryItem = false
            }
        }

        let progress: Double
        if hasExpectedBytesForEveryItem {
            let totalBytes = byteProgress.reduce(0) { $0 + $1.expectedBytes }
            progress = totalBytes > 0
                ? byteProgress.reduce(0) { $0 + $1.progress * $1.expectedBytes } / totalBytes
                : 0
        } else {
            progress = episodeProgress.reduce(0, +) / Double(items.count)
        }

        return DownloadSummary(
            totalCount: items.count,
            completedCount: completedCount,
            activeCount: activeCount,
            resolvingCount: resolvingCount,
            pausedCount: pausedCount,
            failedCount: failedCount,
            progress: min(max(progress, 0), 1)
        )
    }

    /// Backfill series portrait artwork for episode downloads created before
    /// grouped offline-library posters were introduced.
    func ensureSeriesArtwork() {
        guard let currentSession = Container.shared.currentUserSession() else { return }

        let candidates = records.values.filter {
            $0.serverID == currentSession.server.id
                && $0.userID == currentSession.user.id
                && $0.item.type == .episode
                && $0.status == .completed
                && $0.seriesPrimaryImageFilename == nil
                && $0.item.seriesID?.isEmpty == false
        }

        let candidatesBySeries = Dictionary(grouping: candidates) { $0.item.seriesID ?? "" }
        for (seriesID, seriesRecords) in candidatesBySeries
            where !seriesID.isEmpty && pendingSeriesArtworkSeriesIDs.insert(seriesID).inserted
        {
            Task { [weak self] in
                guard let self, let representative = seriesRecords.first else { return }

                let filename = await self.downloadSeriesPrimaryImage(for: representative)
                var updatedRecordIDs: [String] = []

                if let filename {
                    let source = DownloadStorage.folderURL(for: representative)
                        .appendingPathComponent("Images", isDirectory: true)
                        .appendingPathComponent(filename, isDirectory: false)
                    updatedRecordIDs.append(representative.id)
                    for record in seriesRecords.dropFirst() {
                        let destination = DownloadStorage.folderURL(for: record)
                            .appendingPathComponent("Images", isDirectory: true)
                            .appendingPathComponent(filename, isDirectory: false)
                        do {
                            try FileManager.default.createDirectory(
                                at: destination.deletingLastPathComponent(),
                                withIntermediateDirectories: true
                            )
                            try? FileManager.default.removeItem(at: destination)
                            try FileManager.default.copyItem(at: source, to: destination)
                            updatedRecordIDs.append(record.id)
                        } catch {
                            self.logger.debug("Unable to reuse downloaded series artwork: \(error.localizedDescription)")
                        }
                    }
                }

                await MainActor.run {
                    self.pendingSeriesArtworkSeriesIDs.remove(seriesID)
                    guard let filename, updatedRecordIDs.isNotEmpty else { return }

                    self.beginDownloadBatch()
                    var updatedRecords: [DownloadRecord] = []
                    for recordID in updatedRecordIDs {
                        guard var current = self.records[recordID], current.status == .completed else { continue }

                        current.seriesPrimaryImageFilename = filename
                        current.updatedAt = .now
                        self.setRecord(current)
                        updatedRecords.append(current)
                    }
                    self.endDownloadBatch()

                    self.persistenceQueue.async { [weak self] in
                        for record in updatedRecords {
                            self?.writeManifest(record)
                        }
                    }
                }
            }
        }
    }

    // MARK: Commands

    /// Keeps automatic source discovery alive independently of the initiating
    /// view, then hands the resolved items to the persistent background
    /// downloader as one batch.
    @discardableResult
    func download(
        items: [BaseItemDto],
        resolvingWith resolver: @escaping (BaseItemDto) async -> BaseItemDto
    ) -> Bool {
        guard let session = Container.shared.currentUserSession() else { return false }

        var reservedScopes = pendingAutomaticDownloadScopes
        var pendingItems: [BaseItemDto] = []
        var scopes = Set<ItemDownloadScope>()
        for item in items {
            guard let itemID = item.id else { continue }

            let scope = ItemDownloadScope(
                serverID: session.server.id,
                userID: session.user.id,
                presentationItemID: itemID
            )
            guard !reservedScopes.contains(scope) else { continue }

            if let existing = task(for: item) {
                switch existing.state {
                case .cancelled, .error:
                    break
                case .complete, .downloading, .paused, .ready, .resolving:
                    continue
                }
            }
            reservedScopes.insert(scope)
            scopes.insert(scope)
            pendingItems.append(item)
        }
        guard pendingItems.isNotEmpty else { return false }

        let batchID = UUID()
        pendingAutomaticDownloadBatches[batchID] = PendingAutomaticDownloadBatch(
            items: pendingItems,
            scopes: scopes,
            task: nil
        )
        refreshPendingAutomaticDownloadScopes()
        publishPendingAutomaticDownloadChange()

        let transferBatchID = UUID().uuidString
        let preparationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            defer { self.finishPendingAutomaticDownloadBatch(batchID) }

            for item in pendingItems {
                guard !Task.isCancelled, let itemID = item.id else { return }

                let scope = ItemDownloadScope(
                    serverID: session.server.id,
                    userID: session.user.id,
                    presentationItemID: itemID
                )
                guard self.pendingAutomaticDownloadBatches[batchID]?.scopes.contains(scope) == true else {
                    continue
                }

                let resolvedItem = await resolver(item)
                guard !Task.isCancelled else { return }
                guard self.pendingAutomaticDownloadBatches[batchID]?.scopes.contains(scope) == true else {
                    continue
                }

                _ = self.downloadAutomatically(
                    item: resolvedItem,
                    mediaSources: resolvedItem.mediaSources ?? [],
                    batchID: transferBatchID
                )
                self.finishPendingAutomaticDownloadScope(scope, in: batchID)
            }
        }
        if var batch = pendingAutomaticDownloadBatches[batchID] {
            batch.task = preparationTask
            pendingAutomaticDownloadBatches[batchID] = batch
        }
        return true
    }

    @discardableResult
    func download(
        item: BaseItemDto,
        resolvingWith resolver: @escaping (BaseItemDto) async -> BaseItemDto
    ) -> Bool {
        download(items: [item], resolvingWith: resolver)
    }

    func cancelAutomaticDownloadPreparation(for item: BaseItemDto) {
        guard let scope = downloadScope(for: item) else { return }

        cancelPendingAutomaticDownloads(for: [scope])
    }

    @discardableResult
    func download(
        item: BaseItemDto,
        selection: MediaSourceSelectionIntent
    ) -> DownloadTask? {
        switch selection {
        case let .userSelected(mediaSource):
            download(item: item, userSelectedMediaSource: mediaSource)
        case .automatic:
            downloadAutomatically(item: item, mediaSources: item.mediaSources ?? [])
        }
    }

    @discardableResult
    private func download(
        item: BaseItemDto,
        userSelectedMediaSource mediaSource: MediaSourceInfo
    ) -> DownloadTask? {
        guard let session = Container.shared.currentUserSession(),
              let itemID = item.id,
              let mediaSourceID = mediaSource.id
        else { return nil }

        let recordID = DownloadRecord.makeID(
            serverID: session.server.id,
            userID: session.user.id,
            itemID: itemID,
            mediaSourceID: mediaSourceID
        )

        if let existing = taskAdapters[recordID],
           let existingRecord = existing.record,
           isSameSource(existingRecord, mediaSource)
        {
            switch existing.record?.status {
            case .failed, .cancelled:
                retry(task: existing)
            case .paused:
                resume(task: existing)
            default:
                break
            }
            return existing
        }

        let scope = ItemDownloadScope(
            serverID: session.server.id,
            userID: session.user.id,
            presentationItemID: itemID
        )
        let conflicts = records(for: scope)
        if conflicts.isNotEmpty {
            replaceConflictingRecordsThenDownload(
                conflicts: conflicts,
                scope: scope,
                item: item,
                mediaSource: mediaSource,
                batchID: currentDownloadBatchID,
                session: session
            )
            return nil
        }

        return createDownloadRecord(
            item: item,
            mediaSource: mediaSource,
            batchID: currentDownloadBatchID,
            session: session
        )
    }

    /// Queue an item using automatically ranked sources.
    /// Existing active or completed downloads are preserved; failed attempts
    /// are replaced with a fresh ordered fallback plan.
    @discardableResult
    private func downloadAutomatically(
        item: BaseItemDto,
        mediaSources: [MediaSourceInfo],
        batchID: String? = nil
    ) -> DownloadTask? {
        guard let session = Container.shared.currentUserSession(),
              let itemID = item.id
        else { return nil }
        guard let selection = automaticDownloadSelection(
            for: item,
            mediaSources: mediaSources
        ) else { return nil }

        let orderedSources = [selection.selected] + selection.fallbacks
        let firstSource = selection.selected

        let scope = ItemDownloadScope(
            serverID: session.server.id,
            userID: session.user.id,
            presentationItemID: itemID
        )
        let conflicts = records(for: scope)
        if let existing = conflicts.max(by: { $0.updatedAt < $1.updatedAt }) {
            switch existing.status {
            case .failed, .cancelled:
                replaceConflictingRecordsThenDownload(
                    conflicts: conflicts,
                    scope: scope,
                    item: item,
                    mediaSource: firstSource,
                    remainingMediaSources: Array(orderedSources.dropFirst()),
                    batchID: batchID ?? currentDownloadBatchID,
                    session: session
                )
                return nil

            case .completed, .deleting, .downloading, .finalizing, .paused, .queued, .resolving:
                return taskAdapters[existing.id]
            }
        }

        return createDownloadRecord(
            item: item,
            mediaSource: firstSource,
            remainingMediaSources: Array(orderedSources.dropFirst()),
            batchID: batchID ?? currentDownloadBatchID,
            session: session
        )
    }

    func automaticallySelectedDownloadSource(for item: BaseItemDto) -> MediaSourceInfo? {
        automaticDownloadSelection(
            for: item,
            mediaSources: item.mediaSources ?? []
        )?.selected
    }

    private func automaticDownloadSelection(
        for item: BaseItemDto,
        mediaSources: [MediaSourceInfo]
    ) -> MediaSourceSelectionResult? {
        let candidates = mediaSources.filter { source in
            source.id?.isEmpty == false && item.canBeDownloaded(mediaSource: source)
        }
        return MediaSourceSelection.resolve(
            intent: .automatic,
            candidates: candidates,
            policy: .balancedDownload
        )
    }

    /// Enqueue a complete show without publishing and serializing the entire
    /// download index once per episode. A show can have hundreds of episodes;
    /// batching keeps the main thread available while those records are added.
    @discardableResult
    func download(items: [BaseItemDto]) -> [DownloadTask] {
        let previousBatchID = currentDownloadBatchID
        currentDownloadBatchID = UUID().uuidString
        beginDownloadBatch()
        defer {
            endDownloadBatch()
            currentDownloadBatchID = previousBatchID
        }

        return items.compactMap { item in
            download(item: item, selection: .automatic)
        }
    }

    private func createDownloadRecord(
        item: BaseItemDto,
        mediaSource: MediaSourceInfo,
        remainingMediaSources: [MediaSourceInfo]? = nil,
        batchID: String? = nil,
        session: UserSession
    ) -> DownloadTask? {
        guard let itemID = item.id, let mediaSourceID = mediaSource.id else { return nil }

        let recordID = DownloadRecord.makeID(
            serverID: session.server.id,
            userID: session.user.id,
            itemID: itemID,
            mediaSourceID: mediaSourceID
        )

        var record = DownloadRecord(
            serverID: session.server.id,
            userID: session.user.id,
            presentationItemID: itemID,
            mediaSourceID: mediaSourceID,
            item: item,
            mediaSource: mediaSource
        )
        record.remainingMediaSources = remainingMediaSources
        record.batchID = batchID ?? UUID().uuidString
        record.errorDescription = nil
        setRecord(record)
        resolveAndStart(
            recordID: recordID,
            presentationItem: item,
            selectedMediaSource: mediaSource,
            session: session,
            resolutionStartedAt: record.updatedAt
        )

        return taskAdapters[recordID]
    }

    private func replaceConflictingRecordsThenDownload(
        conflicts: [DownloadRecord],
        scope: ItemDownloadScope,
        item: BaseItemDto,
        mediaSource: MediaSourceInfo,
        remainingMediaSources: [MediaSourceInfo]? = nil,
        batchID: String? = nil,
        session: UserSession
    ) {
        guard pendingReplacementScopes.insert(scope).inserted else { return }

        let conflictIDs = Set(conflicts.map(\.id))

        backgroundSession.getAllTasks { [weak self] tasks in
            for transfer in tasks where transfer.taskDescription.map(conflictIDs.contains) == true {
                transfer.cancel()
            }
            DispatchQueue.main.async {
                guard let self else { return }

                let currentConflicts = self.records.values.filter {
                    ItemDownloadScope(record: $0) == scope
                }
                for record in currentConflicts {
                    self.records.removeValue(forKey: record.id)
                    self.taskAdapters.removeValue(forKey: record.id)
                    try? FileManager.default.removeItem(at: DownloadStorage.folderURL(for: record))
                }
                self.publishAdapters()
                self.persist()
                self.pendingReplacementScopes.remove(scope)
                _ = self.createDownloadRecord(
                    item: item,
                    mediaSource: mediaSource,
                    remainingMediaSources: remainingMediaSources,
                    batchID: batchID,
                    session: session
                )
            }
        }
    }

    private func resolveAndStart(
        recordID: String,
        presentationItem: BaseItemDto,
        selectedMediaSource: MediaSourceInfo,
        session: UserSession,
        resolutionStartedAt: Date
    ) {
        pendingResolutions.append(
            PendingResolution(
                recordID: recordID,
                presentationItem: presentationItem,
                selectedMediaSource: selectedMediaSource,
                session: session,
                resolutionStartedAt: resolutionStartedAt
            )
        )
        startPendingResolutions()
    }

    private func startPendingResolutions() {
        while activeResolutionCount < Self.maximumConcurrentResolutions,
              pendingResolutions.isNotEmpty
        {
            let pending = pendingResolutions.removeFirst()
            guard let current = records[pending.recordID],
                  current.status == .resolving,
                  current.updatedAt == pending.resolutionStartedAt
            else { continue }

            activeResolutionCount += 1
            performResolution(pending)
        }
    }

    private func performResolution(_ pending: PendingResolution) {
        Task { [weak self] in
            guard let self else { return }

            do {
                let resolution = try await self.resolveDownloadItem(
                    presentationItem: pending.presentationItem,
                    selectedMediaSource: pending.selectedMediaSource,
                    session: pending.session
                )
                await MainActor.run {
                    defer { self.finishResolution() }
                    guard var current = self.records[pending.recordID],
                          current.status == .resolving,
                          current.updatedAt == pending.resolutionStartedAt
                    else { return }

                    current.resolvedDownloadItemID = resolution.itemID
                    current.transferStrategy = resolution.strategy
                    current.item = resolution.item
                    current.mediaSource = resolution.mediaSource
                    current.expectedBytes = MediaSourceSelection.estimatedSize(for: resolution.mediaSource)
                        ?? current.expectedBytes
                    current.status = .queued
                    current.errorDescription = nil
                    current.updatedAt = .now
                    // The queued state is immediately followed by transfer
                    // creation, so avoid a redundant full publication and
                    // persistence checkpoint between the two transitions.
                    self.records[pending.recordID] = current
                    self.startTransfer(recordID: pending.recordID)
                }
            } catch {
                await MainActor.run {
                    defer { self.finishResolution() }
                    guard let current = self.records[pending.recordID],
                          current.status == .resolving,
                          current.updatedAt == pending.resolutionStartedAt
                    else { return }

                    self.fail(recordID: pending.recordID, error: error)
                }
            }
        }
    }

    private func finishResolution() {
        activeResolutionCount = max(0, activeResolutionCount - 1)
        startPendingResolutions()
    }

    /// Compatibility entry point used by the existing download detail view.
    func download(task: DownloadTask) {
        if task.record != nil {
            retry(task: task)
        } else if let mediaSource = task.mediaSource ?? task.item.mediaSources?.first {
            _ = download(item: task.item, selection: .userSelected(mediaSource))
        }
    }

    func pause(task: DownloadTask) {
        guard var record = task.record,
              records[record.id]?.createdAt == record.createdAt
        else { return }

        record.status = .paused
        record.updatedAt = .now
        setRecord(record)
        backgroundSession.getAllTasks { tasks in
            tasks.first(where: {
                $0.taskDescription == record.id
                    && $0.taskIdentifier == record.transferTaskIdentifier
            })?.suspend()
        }
    }

    func resume(task: DownloadTask) {
        guard var record = task.record,
              records[record.id]?.createdAt == record.createdAt
        else { return }

        backgroundSession.getAllTasks { [weak self] tasks in
            if let transfer = tasks.first(where: {
                $0.taskDescription == record.id
                    && $0.taskIdentifier == record.transferTaskIdentifier
            }) {
                transfer.resume()
                DispatchQueue.main.async {
                    guard self?.records[record.id]?.createdAt == record.createdAt else { return }

                    record.status = .downloading
                    record.updatedAt = .now
                    self?.setRecord(record)
                }
            } else {
                DispatchQueue.main.async {
                    guard self?.records[record.id]?.createdAt == record.createdAt else { return }

                    self?.startTransfer(recordID: record.id)
                }
            }
        }
    }

    func retry(task: DownloadTask) {
        guard var record = task.record else {
            if let mediaSource = task.mediaSource ?? task.item.mediaSources?.first {
                _ = download(item: task.item, selection: .userSelected(mediaSource))
            }
            return
        }
        guard records[record.id]?.createdAt == record.createdAt else { return }
        guard let session = session(for: record) else {
            fail(recordID: record.id, error: DownloadError.missingSession)
            return
        }

        record.status = .resolving
        record.progress = 0
        record.bytesWritten = 0
        record.expectedBytes = MediaSourceSelection.estimatedSize(for: record.mediaSource)
            ?? record.expectedBytes
        record.transferTaskIdentifier = nil
        record.errorDescription = nil
        record.updatedAt = .now
        setRecord(record)
        let resolutionStartedAt = record.updatedAt
        let recordID = record.id
        backgroundSession.getAllTasks { [weak self] tasks in
            for transfer in tasks where transfer.taskDescription == recordID {
                transfer.cancel()
            }
            DispatchQueue.main.async {
                guard let self,
                      let current = self.records[recordID],
                      current.status == .resolving,
                      current.updatedAt == resolutionStartedAt
                else { return }

                self.resolveAndStart(
                    recordID: recordID,
                    presentationItem: current.item,
                    selectedMediaSource: current.mediaSource,
                    session: session,
                    resolutionStartedAt: resolutionStartedAt
                )
            }
        }
    }

    func cancel(task: DownloadTask) {
        guard let record = task.record,
              records[record.id]?.createdAt == record.createdAt
        else { return }

        discardRecords([record])
    }

    func delete(task: DownloadTask) {
        guard let record = task.record,
              records[record.id]?.createdAt == record.createdAt
        else { return }

        discardRecords([record])
    }

    /// Fully discard an attempt instead of retaining a hidden cancelled
    /// record. The package is moved out of its stable location before the
    /// asynchronous transfer and file cleanup, so an immediate retry cannot
    /// inherit metadata or artwork from the aborted attempt.
    private func discardRecords(_ candidates: [DownloadRecord]) {
        guard candidates.isNotEmpty else { return }

        let recordsByID = Dictionary(
            candidates.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let recordIDs = Set(recordsByID.keys)

        let stagedFolders = removeRecordsFromLibrary(Array(recordsByID.values))

        backgroundSession.getAllTasks { tasks in
            for transfer in tasks where transfer.taskDescription.map(recordIDs.contains) == true {
                transfer.cancel()
            }
        }
        deleteStagedFolders(stagedFolders)
    }

    /// Remove cancelled records written by older versions now that aborting a
    /// download discards the attempt completely.
    private func discardCancelledRecords() {
        discardRecords(records.values.filter { $0.status == .cancelled })
    }

    private func removeRecordsFromLibrary(_ candidates: [DownloadRecord]) -> [URL] {
        var stagedFolders: [URL] = []
        var removedRecordIDs = Set<String>()

        for record in candidates {
            guard records[record.id]?.createdAt == record.createdAt else { continue }

            if let stagedFolder = stageDownloadFolderForDeletion(record) {
                stagedFolders.append(stagedFolder)
            }
            records.removeValue(forKey: record.id)
            taskAdapters.removeValue(forKey: record.id)
            lastProgressPublicationDates.removeValue(forKey: record.id)
            let scope = ItemDownloadScope(record: record)
            if recordIDsByScope[scope] == record.id {
                recordIDsByScope.removeValue(forKey: scope)
            }
            removedRecordIDs.insert(record.id)
        }

        guard removedRecordIDs.isNotEmpty else { return stagedFolders }

        pendingResolutions.removeAll { removedRecordIDs.contains($0.recordID) }
        pendingFinalizationRecordIDs.removeAll { removedRecordIDs.contains($0) }
        publishAdapters()
        persist(after: 0)
        return stagedFolders
    }

    private func stageDownloadFolderForDeletion(_ record: DownloadRecord) -> URL? {
        let source = DownloadStorage.folderURL(for: record)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }

        let deletionRoot = DownloadStorage.rootURL
            .appendingPathComponent("PendingDeletion", isDirectory: true)
        let destination = deletionRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: deletionRoot, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        } catch {
            logger.error("Unable to stage download package for deletion: \(error.localizedDescription)")
            return nil
        }
    }

    private func deleteStagedFolders(_ folders: [URL]) {
        guard folders.isNotEmpty else { return }

        fileIOQueue.async {
            for folder in folders {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }

    private func clearPendingDeletionFolders() {
        let deletionRoot = DownloadStorage.rootURL
            .appendingPathComponent("PendingDeletion", isDirectory: true)
        fileIOQueue.async {
            try? FileManager.default.removeItem(at: deletionRoot)
        }
    }

    func clearTmp() {
        let staging = DownloadStorage.rootURL.appendingPathComponent("Staging", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
    }

    // MARK: Resolution

    private struct DownloadResolution {
        let itemID: String
        let strategy: DownloadTransferStrategy
        let item: BaseItemDto
        let mediaSource: MediaSourceInfo
    }

    /// Resolves the exact selected source and chooses its persisted transfer
    /// strategy. File-backed versions use the policy-enforcing item download;
    /// finite HTTP sources prefer the refreshed provider URL directly.
    private func resolveDownloadItem(
        presentationItem: BaseItemDto,
        selectedMediaSource: MediaSourceInfo,
        session: UserSession
    ) async throws -> DownloadResolution {
        guard presentationItem.id != nil else { throw DownloadError.invalidItem }
        guard [.movie, .episode].contains(presentationItem.type) else { throw DownloadError.unsupportedItem }
        guard session.user.data.policy?.enableContentDownloading == true else {
            throw DownloadError.versionIsNotDownloadable
        }
        guard selectedMediaSource.id != nil else { throw DownloadError.missingMediaSource }

        switch DownloadSourceClassifier.kind(
            itemIsLive: presentationItem.isLiveStream,
            source: selectedMediaSource
        ) {
        case .live:
            throw DownloadError.unsupportedLiveStream

        case .disc:
            throw DownloadError.unsupportedDiscMedia

        case .hls:
            throw DownloadError.unsupportedHLS

        case .unsupported:
            throw DownloadError.unsupportedRemoteOrPluginSource

        case .finiteHTTP:
            return try await resolveFiniteHTTPDownload(
                presentationItem: presentationItem,
                selectedMediaSource: selectedMediaSource,
                session: session
            )

        case .file:
            return try await resolveFileDownload(
                presentationItem: presentationItem,
                selectedMediaSource: selectedMediaSource,
                session: session
            )
        }
    }

    private func resolveFiniteHTTPDownload(
        presentationItem: BaseItemDto,
        selectedMediaSource: MediaSourceInfo,
        session: UserSession
    ) async throws -> DownloadResolution {
        guard let presentationItemID = presentationItem.id,
              let mediaSourceID = selectedMediaSource.id
        else { throw DownloadError.invalidItem }

        let selectedDirectURL = DownloadSourceClassifier.directHTTPURL(for: selectedMediaSource)

        let currentItem: BaseItemDto
        do {
            currentItem = try await refreshedItemWithMediaSources(
                itemID: presentationItemID,
                userID: session.user.id,
                session: session
            )
        } catch {
            logger.warning(
                "Unable to refresh finite HTTP download source",
                metadata: [
                    "presentationItemID": .string(presentationItemID),
                    "mediaSourceID": .string(mediaSourceID),
                    "error": .string(error.localizedDescription),
                ]
            )
            throw DownloadError.versionCouldNotBeResolved
        }

        guard currentItem.id == presentationItemID,
              currentItem.type == presentationItem.type
        else { throw DownloadError.versionCouldNotBeResolved }

        let availableSources = currentItem.mediaSources?.isNotEmpty == true
            ? currentItem.mediaSources ?? []
            : presentationItem.mediaSources ?? []
        guard let refreshedSource = DownloadSourceClassifier.exactSelection(
            selectedMediaSource,
            in: availableSources
        ),
            refreshedSource.id == mediaSourceID,
            availableSources.count(where: { $0.id == mediaSourceID }) == 1
        else { throw DownloadError.versionCouldNotBeResolved }

        switch DownloadSourceClassifier.kind(
            itemIsLive: currentItem.isLiveStream,
            source: refreshedSource
        ) {
        case .finiteHTTP:
            break
        case .hls:
            throw DownloadError.unsupportedHLS
        case .live:
            throw DownloadError.unsupportedLiveStream
        case .disc:
            throw DownloadError.unsupportedRemoteOrPluginSource
        case .file, .unsupported:
            // Opaque plugin paths such as gelato://stub are intentionally not
            // fetched by URLSession. This function was entered from an exact
            // source labelled HTTP, so let Jellyfin's static stream endpoint
            // proxy it when neither refresh path exposes an HTTP(S) URL.
            break
        }

        var resolvedSource = refreshedSource
        var playbackDirectStreamURL: URL?
        do {
            let playback = try await exactPlaybackInfo(
                itemID: presentationItemID,
                source: refreshedSource,
                session: session
            )
            let responseSources = playback.playbackInfo.mediaSources ?? []
            let exactPlaybackDirectStreamURL = try exactDirectStreamURL(
                from: playback.directStreamMediaSources,
                mediaSourceID: mediaSourceID,
                session: session
            )
            if responseSources.isNotEmpty {
                guard let playbackSource = DownloadSourceClassifier.exactSelection(
                    refreshedSource,
                    in: responseSources
                ),
                    playbackSource.id == mediaSourceID,
                    responseSources.count(where: { $0.id == mediaSourceID }) == 1
                else { throw DownloadError.versionCouldNotBeResolved }

                switch DownloadSourceClassifier.kind(
                    itemIsLive: currentItem.isLiveStream,
                    source: playbackSource
                ) {
                case .finiteHTTP:
                    resolvedSource = playbackSource

                case .hls:
                    throw DownloadError.unsupportedHLS

                case .live:
                    throw DownloadError.unsupportedLiveStream

                case .file, .unsupported:
                    if exactPlaybackDirectStreamURL != nil {
                        resolvedSource = playbackSource
                    }

                case .disc:
                    throw DownloadError.unsupportedRemoteOrPluginSource
                }
            }

            playbackDirectStreamURL = exactPlaybackDirectStreamURL
        } catch let error as DownloadError {
            throw error
        } catch {
            // The normal item response may already contain a fresh provider
            // URL. PlaybackInfo is an additional refresh path, not permission
            // to select a different source when it is unavailable.
            logger.warning(
                "Exact-source PlaybackInfo refresh failed; using the refreshed item source if possible",
                metadata: [
                    "presentationItemID": .string(presentationItemID),
                    "mediaSourceID": .string(mediaSourceID),
                    "error": .string(error.localizedDescription),
                ]
            )
        }

        let refreshedDirectPlayURL: URL? = if resolvedSource.isSupportsDirectPlay == true {
            DownloadSourceClassifier.directHTTPURL(for: resolvedSource)
                ?? DownloadSourceClassifier.directHTTPURL(for: refreshedSource)
                ?? selectedDirectURL
        } else {
            nil
        }
        if let directURL = playbackDirectStreamURL ?? refreshedDirectPlayURL {
            // Persist the newly resolved signed URL for background URLSession.
            // It is refreshed again on every explicit retry.
            var requiredHeaders = refreshedSource.requiredHTTPHeaders ?? [:]
            requiredHeaders.merge(selectedMediaSource.requiredHTTPHeaders ?? [:]) { current, _ in
                current
            }
            requiredHeaders.merge(resolvedSource.requiredHTTPHeaders ?? [:]) { _, refreshed in
                refreshed
            }
            resolvedSource.requiredHTTPHeaders = requiredHeaders.isEmpty ? nil : requiredHeaders
            resolvedSource.path = directURL.absoluteString
            resolvedSource.protocol = .http
            return DownloadResolution(
                itemID: presentationItemID,
                strategy: .directHTTPSource,
                item: currentItem,
                mediaSource: resolvedSource
            )
        }

        // Keep the Jellyfin proxy only for exact finite HTTP sources whose
        // provider URL is not safely exposed by either item or PlaybackInfo.
        return DownloadResolution(
            itemID: presentationItemID,
            strategy: .staticHTTPStream,
            item: currentItem,
            mediaSource: resolvedSource
        )
    }

    private func refreshedItemWithMediaSources(
        itemID: String,
        userID: String,
        session: UserSession
    ) async throws -> BaseItemDto {
        var item = try await session.client
            .send(
                Paths.getItem(itemID: itemID, userID: userID)
            )
            .value

        var parameters = Paths.GetItemsParameters()
        parameters.fields = .MediaSourceFields
        parameters.ids = [itemID]
        parameters.limit = 1
        if let sourceItem = try? await session.client
            .send(
                Paths.getItems(parameters: parameters)
            )
            .value
            .items?
            .first,
            let mediaSources = sourceItem.mediaSources,
            mediaSources.isNotEmpty
        {
            item.mediaSources = mediaSources
            item.mediaSourceCount = sourceItem.mediaSourceCount ?? mediaSources.count
        }
        return item
    }

    private func exactPlaybackInfo(
        itemID: String,
        source: MediaSourceInfo,
        session: UserSession
    ) async throws -> PlaybackInfoResponseEnvelope {
        var playbackInfo = PlaybackInfoDto()
        playbackInfo.enableDirectPlay = true
        playbackInfo.enableDirectStream = true
        playbackInfo.enableTranscoding = false
        playbackInfo.userID = session.user.id
        playbackInfo.mediaSourceID = source.id

        let parameters = Paths.GetPostedPlaybackInfoParameters(
            userID: session.user.id,
            mediaSourceID: source.id
        )
        return try await session.client
            .send(
                Paths.getPostedPlaybackInfo(
                    itemID: itemID,
                    parameters: parameters,
                    playbackInfo
                )
                .withResponse(PlaybackInfoResponseEnvelope.self)
            )
            .value
    }

    private func exactDirectStreamURL(
        from sources: [PlaybackInfoResponseEnvelope.DirectStreamMediaSource],
        mediaSourceID: String,
        session: UserSession
    ) throws -> URL? {
        let matches = sources.filter {
            $0.id == mediaSourceID
                && ($0.playMethod == nil || $0.playMethod == PlayMethod.directStream.rawValue)
        }
        guard matches.count == 1,
              let value = matches[0].directStreamURL,
              !value.isEmpty
        else { return nil }

        if let pathExtension = URL(string: value)?.pathExtension.lowercased(),
           ["m3u", "m3u8"].contains(pathExtension)
        {
            throw DownloadError.unsupportedHLS
        }

        if let absoluteURL = URL(string: value), absoluteURL.scheme != nil {
            return DownloadSourceClassifier.finiteHTTPURL(from: value)
        }
        guard !value.hasPrefix("//"), let serverURL = session.client.url(path: value) else { return nil }

        return DownloadSourceClassifier.finiteHTTPURL(from: serverURL.absoluteString)
    }

    private func resolveFileDownload(
        presentationItem: BaseItemDto,
        selectedMediaSource: MediaSourceInfo,
        session: UserSession
    ) async throws -> DownloadResolution {
        guard let presentationItemID = presentationItem.id,
              let mediaSourceID = selectedMediaSource.id
        else { throw DownloadError.invalidItem }

        if mediaSourceID == presentationItemID,
           let sources = presentationItem.mediaSources,
           DownloadSourceClassifier.exactSelection(selectedMediaSource, in: sources) != sources.first
        {
            throw DownloadError.versionCouldNotBeResolved
        }

        if mediaSourceID == presentationItemID, presentationItem.canDownload == true {
            return DownloadResolution(
                itemID: presentationItemID,
                strategy: .itemDownload,
                item: presentationItem,
                mediaSource: selectedMediaSource
            )
        }

        let candidate: BaseItemDto
        do {
            candidate = try await session.client
                .send(
                    Paths.getItem(itemID: mediaSourceID, userID: session.user.id)
                )
                .value
        } catch {
            throw DownloadError.versionCouldNotBeResolved
        }
        guard candidate.id == mediaSourceID,
              candidate.type == presentationItem.type,
              candidate.canDownload == true
        else { throw DownloadError.versionIsNotDownloadable }

        return DownloadResolution(
            itemID: mediaSourceID,
            strategy: .itemDownload,
            item: presentationItem,
            mediaSource: selectedMediaSource
        )
    }

    // MARK: Transfer setup

    private func startTransfer(recordID: String) {
        guard var record = records[recordID], let session = session(for: record) else {
            fail(recordID: recordID, error: DownloadError.missingSession)
            return
        }
        guard session.user.data.policy?.enableContentDownloading == true else {
            fail(recordID: recordID, error: DownloadError.versionIsNotDownloadable)
            return
        }

        let strategy = record.transferStrategy
            ?? DownloadSourceClassifier.inferredStrategy(
                itemIsLive: record.item.isLiveStream,
                source: record.mediaSource
            )
        let url: URL
        var requiresJellyfinAuthorization = false
        switch strategy {
        case .itemDownload:
            guard let resolvedItemID = record.resolvedDownloadItemID else {
                fail(recordID: recordID, error: DownloadError.versionCouldNotBeResolved)
                return
            }
            guard let downloadURL = session.client.url(with: Paths.getDownload(itemID: resolvedItemID)) else {
                fail(recordID: recordID, error: DownloadError.invalidItem)
                return
            }

            url = downloadURL
            requiresJellyfinAuthorization = true

        case .directHTTPSource:
            guard let directURL = DownloadSourceClassifier.directHTTPURL(for: record.mediaSource) else {
                fail(recordID: recordID, error: DownloadError.unsupportedRemoteOrPluginSource)
                return
            }

            url = directURL
            requiresJellyfinAuthorization = isSameOrigin(
                directURL,
                session.client.configuration.url
            )

        case .staticHTTPStream:
            // This is Jellyfin's exact-source static playback proxy, not a
            // version fallback. The app-side download policy gate above is
            // intentionally rechecked for every retry/relaunch.
            let parameters = Paths.GetVideoStreamParameters(
                container: DownloadSourceClassifier.routeContainer(for: record.mediaSource),
                isStatic: true,
                mediaSourceID: record.mediaSourceID,
                deviceID: session.client.configuration.deviceID
            )
            let apiRequest = Paths.getVideoStream(
                itemID: record.presentationItemID,
                parameters: parameters
            )
            guard let staticURL = session.client.url(with: apiRequest) else {
                fail(recordID: recordID, error: DownloadError.invalidItem)
                return
            }

            url = staticURL
            requiresJellyfinAuthorization = true

        case nil:
            fail(recordID: recordID, error: DownloadError.unsupportedRemoteOrPluginSource)
            return
        }
        record.transferStrategy = strategy

        do {
            try DownloadStorage.createFolder(for: record)
        } catch {
            fail(recordID: recordID, error: error)
            return
        }

        #if os(iOS)
        let storageValues = try? DownloadStorage.rootURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        let availableCapacity = storageValues?.volumeAvailableCapacityForImportantUsage

        if let expectedBytes = record.expectedBytes,
           let availableCapacity,
           availableCapacity < expectedBytes
        {
            fail(recordID: recordID, error: DownloadError.notEnoughStorage)
            return
        }
        #endif

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if requiresJellyfinAuthorization {
            request.setValue(authorizationHeader(for: session), forHTTPHeaderField: "Authorization")
        }
        if strategy == .directHTTPSource, !requiresJellyfinAuthorization {
            applyRequiredHTTPHeaders(record.mediaSource.requiredHTTPHeaders, to: &request)
        }

        let transfer = backgroundSession.downloadTask(with: request)
        transfer.taskDescription = record.id
        record.status = .downloading
        record.transferTaskIdentifier = transfer.taskIdentifier
        record.errorDescription = nil
        record.updatedAt = .now
        setRecord(record)
        transfer.resume()
    }

    private func applyRequiredHTTPHeaders(_ headers: [String: String]?, to request: inout URLRequest) {
        let unsafeHeaders: Set<String> = [
            "connection",
            "content-length",
            "host",
            "keep-alive",
            "proxy-authorization",
            "proxy-connection",
            "te",
            "trailer",
            "transfer-encoding",
            "upgrade",
        ]
        let allowedNameCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~"
        )
        for (name, value) in headers ?? [:]
            where !unsafeHeaders.contains(name.lowercased())
            && name.unicodeScalars.allSatisfy({ allowedNameCharacters.contains($0) })
            && !value.contains("\r")
            && !value.contains("\n")
        {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    private func isSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(for: lhs) == effectivePort(for: rhs)
    }

    private func effectivePort(for url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    private func authorizationHeader(for session: UserSession) -> String {
        let configuration = session.client.configuration
        let fields = [
            "DeviceId=\(configuration.deviceID)",
            "Device=\(configuration.deviceName)",
            "Client=\(configuration.client)",
            "Version=\(configuration.version)",
            "Token=\(session.user.accessToken)",
        ]
        return "MediaBrowser \(fields.joined(separator: ", "))"
    }

    private func session(for record: DownloadRecord) -> UserSession? {
        if let current = Container.shared.currentUserSession(),
           current.server.id == record.serverID,
           current.user.id == record.userID
        {
            return current
        }

        guard let server = StoredValues[.Server.servers].first(where: { $0.id == record.serverID }),
              let user = StoredValues[.User.users].first(where: {
                  $0.id == record.userID && $0.serverID == record.serverID
              })
        else { return nil }

        return UserSession(server: server, user: user)
    }

    // MARK: Persistence

    private func setRecord(_ record: DownloadRecord) {
        let wasVisibleInDownloadLibrary = records[record.id]
            .map(Self.isVisibleInDownloadLibrary) ?? false
        records[record.id] = record
        recordIDsByScope[ItemDownloadScope(record: record)] = record.id
        if ![.downloading, .paused].contains(record.status) {
            lastProgressPublicationDates.removeValue(forKey: record.id)
        }
        let isNewAdapter = taskAdapters[record.id] == nil
        if let adapter = taskAdapters[record.id] {
            adapter.update(record: record)
        } else {
            taskAdapters[record.id] = DownloadTask(
                item: record.item,
                mediaSource: record.mediaSource,
                record: record
            )
        }
        let isVisibleInDownloadLibrary = Self.isVisibleInDownloadLibrary(record)
        refreshAdaptersAndPersist(
            publishCollection: isNewAdapter
                || wasVisibleInDownloadLibrary != isVisibleInDownloadLibrary
        )
    }

    /// Cancelled records from an interrupted migration or older release are
    /// not offline content and must never keep an item in the library.
    private static func isVisibleInDownloadLibrary(_ record: DownloadRecord) -> Bool {
        ![.cancelled, .deleting].contains(record.status)
    }

    /// Progress callbacks arrive many times per second. Updating the task is
    /// enough for the visible progress view; serializing every record and
    /// republishing the collection for each callback makes large show
    /// downloads noticeably stall navigation.
    private func setProgressRecord(_ record: DownloadRecord) {
        records[record.id] = record
        scheduleProgressPersistence()

        let now = Date.now
        let lastPublication = lastProgressPublicationDates[record.id] ?? .distantPast
        guard now.timeIntervalSince(lastPublication) >= Self.progressPublicationInterval
        else { return }

        lastProgressPublicationDates[record.id] = now
        // Byte counts can change even when a server does not expose a usable
        // content length and the fractional progress remains zero. The
        // manager has already throttled this path, so explicitly publish the
        // update for byte labels and indeterminate progress controls.
        taskAdapters[record.id]?.update(record: record, forcePublication: true)
        scheduleAggregateRefresh()
    }

    private func beginDownloadBatch() {
        downloadBatchDepth += 1
    }

    private func endDownloadBatch() {
        precondition(downloadBatchDepth > 0, "Unbalanced download batch")
        downloadBatchDepth -= 1
        guard downloadBatchDepth == 0, needsRefreshAfterDownloadBatch else { return }

        needsRefreshAfterDownloadBatch = false
        publishAdapters()
        persist()
    }

    private func refreshAdaptersAndPersist(publishCollection: Bool) {
        guard downloadBatchDepth == 0 else {
            needsRefreshAfterDownloadBatch = true
            return
        }

        if publishCollection {
            publishAdapters()
        } else {
            scheduleAggregateRefresh()
        }
        persist()
    }

    private func scheduleProgressPersistence() {
        guard !isProgressPersistenceScheduled else { return }

        isProgressPersistenceScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.progressPersistenceInterval) { [weak self] in
            guard let self else { return }

            self.isProgressPersistenceScheduled = false
            self.persist(storeInDatabase: false)
        }
    }

    private func scheduleAggregateRefresh() {
        guard !isAggregateRefreshScheduled else { return }

        isAggregateRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }

            self.isAggregateRefreshScheduled = false
            self.aggregateUpdates.send()
        }
    }

    private func fail(recordID: String, error: Error, diagnostic: String? = nil) {
        guard var record = records[recordID] else { return }

        if advanceToNextMediaSource(record: record, after: error) {
            return
        }

        let sourceURL = record.mediaSource.path.flatMap(URL.init(string:))
        record.status = .failed
        record.errorDescription = [error.localizedDescription, diagnostic]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " ")
        record.transferTaskIdentifier = nil
        record.updatedAt = .now
        setRecord(record)
        logger.error(
            "Download failed: \(record.errorDescription ?? error.localizedDescription)",
            metadata: [
                "recordID": .string(recordID),
                "presentationItemID": .string(record.presentationItemID),
                "mediaSourceID": .string(record.mediaSourceID),
                "mediaProtocol": .string(record.mediaSource.protocol?.rawValue ?? "unknown"),
                "transferStrategy": .string(record.transferStrategy?.rawValue ?? "legacy-unresolved"),
                "isRemote": .stringConvertible(record.mediaSource.isRemote ?? false),
                "isInfiniteStream": .stringConvertible(record.mediaSource.isInfiniteStream ?? false),
                "videoType": .string(record.mediaSource.videoType?.rawValue ?? "unknown"),
                "remainingVersionCount": .stringConvertible(record.remainingMediaSources?.count ?? 0),
                "itemPathExtension": .string(record.item.path.map { URL(fileURLWithPath: $0).pathExtension } ?? "missing"),
                "sourceURLScheme": .string(sourceURL?.scheme ?? "missing"),
                "sourceURLHost": .string(sourceURL?.host ?? "missing"),
            ]
        )
    }

    private func advanceToNextMediaSource(record: DownloadRecord, after error: Error) -> Bool {
        guard shouldTryNextMediaSource(after: error),
              let nextSource = record.remainingMediaSources?.first,
              let session = session(for: record)
        else { return false }

        let remainingSources = Array((record.remainingMediaSources ?? []).dropFirst())
        var resolvingRecord = record
        resolvingRecord.status = .resolving
        resolvingRecord.progress = 0
        resolvingRecord.bytesWritten = 0
        resolvingRecord.expectedBytes = MediaSourceSelection.estimatedSize(for: nextSource)
        resolvingRecord.transferTaskIdentifier = nil
        resolvingRecord.errorDescription = nil
        resolvingRecord.updatedAt = .now
        setRecord(resolvingRecord)

        logger.warning(
            "Download source failed; trying the next version",
            metadata: [
                "presentationItemID": .string(record.presentationItemID),
                "failedMediaSourceID": .string(record.mediaSourceID),
                "nextMediaSourceID": .string(nextSource.id ?? "missing"),
                "remainingVersionCount": .stringConvertible(remainingSources.count),
            ]
        )

        backgroundSession.getAllTasks { [weak self] tasks in
            for transfer in tasks where transfer.taskDescription == record.id {
                transfer.cancel()
            }
            DispatchQueue.main.async {
                guard let self,
                      let current = self.records[record.id],
                      current.createdAt == record.createdAt,
                      current.status == .resolving,
                      current.updatedAt == resolvingRecord.updatedAt
                else { return }

                var presentationItem = record.item
                presentationItem.id = record.presentationItemID
                presentationItem.mediaSourceCount = remainingSources.count + 1
                presentationItem.mediaSources = [nextSource] + remainingSources

                self.records.removeValue(forKey: record.id)
                self.taskAdapters.removeValue(forKey: record.id)
                try? FileManager.default.removeItem(at: DownloadStorage.folderURL(for: record))
                self.publishAdapters()
                self.persist()

                _ = self.createDownloadRecord(
                    item: presentationItem,
                    mediaSource: nextSource,
                    remainingMediaSources: remainingSources,
                    batchID: record.batchID,
                    session: session
                )
            }
        }

        return true
    }

    private func shouldTryNextMediaSource(after error: Error) -> Bool {
        guard let downloadError = error as? DownloadError else { return true }

        return switch downloadError {
        case .invalidItem, .missingMediaSource, .missingSession, .notEnoughStorage, .unsupportedItem:
            false
        case .invalidResponse, .invalidUpstreamResponse, .staticProxyFailed, .unsupportedDiscMedia,
             .unsupportedHLS, .unsupportedLiveStream, .unsupportedRemoteOrPluginSource,
             .upstreamHTTPError, .upstreamTransportError, .versionCouldNotBeResolved,
             .versionIsNotDownloadable:
            true
        }
    }

    private func publishAdapters() {
        downloads = taskAdapters.values.sorted {
            ($0.record?.createdAt ?? .distantPast) > ($1.record?.createdAt ?? .distantPast)
        }
        taskAdaptersByScope = downloads.reduce(into: [:]) { result, task in
            guard let record = task.record else { return }

            let scope = ItemDownloadScope(record: record)
            if result[scope] == nil {
                result[scope] = task
            }
        }
        taskAdaptersBySeries = Dictionary(
            grouping: downloads.compactMap { task -> (SeriesDownloadScope, DownloadTask)? in
                guard let record = task.record, let seriesID = record.item.seriesID else { return nil }

                return (
                    SeriesDownloadScope(
                        serverID: record.serverID,
                        userID: record.userID,
                        seriesID: seriesID
                    ),
                    task
                )
            },
            by: \.0
        ).mapValues { $0.map(\.1) }
        aggregateUpdates.send()
    }

    private func rebuildAdapters() {
        taskAdapters = taskAdapters.filter { records[$0.key] != nil }
        recordIDsByScope.removeAll(keepingCapacity: true)
        for record in records.values {
            recordIDsByScope[ItemDownloadScope(record: record)] = record.id
            if let adapter = taskAdapters[record.id] {
                adapter.update(record: record)
            } else {
                taskAdapters[record.id] = DownloadTask(
                    item: record.item,
                    mediaSource: record.mediaSource,
                    record: record
                )
            }
        }
        publishAdapters()
    }

    private func records(for scope: ItemDownloadScope) -> [DownloadRecord] {
        guard let recordID = recordIDsByScope[scope] else { return [] }
        guard let record = records[recordID] else {
            recordIDsByScope.removeValue(forKey: scope)
            return []
        }

        return [record]
    }

    private func isSameSource(_ record: DownloadRecord, _ mediaSource: MediaSourceInfo?) -> Bool {
        guard record.mediaSourceID == mediaSource?.id else { return false }

        if let recordETag = record.mediaSource.eTag?.nilIfEmpty,
           let selectedETag = mediaSource?.eTag?.nilIfEmpty
        {
            return recordETag == selectedETag
        }
        return true
    }

    /// Older stores could contain one record per version. Keep only the most
    /// recently updated record for each movie/episode and remove every stale
    /// transfer and version-specific storage folder.
    @discardableResult
    private func normalizeDuplicateRecords() -> Bool {
        let groups = Dictionary(grouping: records.values) { ItemDownloadScope(record: $0) }
        var obsoleteRecords: [DownloadRecord] = []

        for group in groups.values where group.count > 1 {
            guard let newest = group.max(by: { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id < rhs.id
            }) else { continue }

            obsoleteRecords.append(contentsOf: group.filter { $0.id != newest.id })
        }
        guard obsoleteRecords.isNotEmpty else { return false }

        let obsoleteIDs = Set(obsoleteRecords.map(\.id))
        backgroundSession.getAllTasks { tasks in
            for transfer in tasks where transfer.taskDescription.map(obsoleteIDs.contains) == true {
                transfer.cancel()
            }
        }
        for record in obsoleteRecords {
            records.removeValue(forKey: record.id)
            taskAdapters.removeValue(forKey: record.id)
            try? FileManager.default.removeItem(at: DownloadStorage.folderURL(for: record))
        }
        publishAdapters()
        return true
    }

    private func normalizeTransferStrategies() {
        for (id, var record) in records where record.transferStrategy == nil {
            // Before this field existed all finite HTTP records used the
            // Jellyfin static proxy. Preserve that route until an explicit
            // Retry refreshes the source and promotes it to direct HTTP.
            record.transferStrategy = switch DownloadSourceClassifier.kind(
                itemIsLive: record.item.isLiveStream,
                source: record.mediaSource
            ) {
            case .file: .itemDownload
            case .finiteHTTP: .staticHTTPStream
            case .disc, .hls, .live, .unsupported: nil
            }
            records[id] = record
        }
    }

    private func persist(
        storeInDatabase: Bool = true,
        after delay: TimeInterval = DownloadManager.persistenceDebounceInterval,
        completion: (() -> Void)? = nil
    ) {
        pendingPersistenceRequiresStore = pendingPersistenceRequiresStore
            || (storeInDatabase && isStorePrepared)
        pendingPersistenceWorkItem?.cancel()

        if let completion {
            persistenceDrainCompletions.append(completion)
            pendingPersistenceWorkItem = nil
            enqueueCurrentPersistenceSnapshot()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.enqueueCurrentPersistenceSnapshot()
        }
        pendingPersistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func enqueueCurrentPersistenceSnapshot() {
        let snapshot = PersistenceSnapshot(
            values: records.values.sorted { $0.createdAt < $1.createdAt },
            shouldStore: pendingPersistenceRequiresStore
        )
        pendingPersistenceRequiresStore = false
        enqueuePersistenceSnapshot(snapshot)
    }

    private func enqueuePersistenceSnapshot(_ snapshot: PersistenceSnapshot) {
        guard !isPersistenceWriteInFlight else {
            if var pending = pendingPersistenceSnapshot {
                pending.values = snapshot.values
                pending.shouldStore = pending.shouldStore || snapshot.shouldStore
                pendingPersistenceSnapshot = pending
            } else {
                pendingPersistenceSnapshot = snapshot
            }
            return
        }

        isPersistenceWriteInFlight = true
        persistenceQueue.async { [weak self] in
            guard let self else { return }

            let encodedData = self.writePersistenceFile(snapshot.values)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                if snapshot.shouldStore, let encodedData {
                    self.storePersistenceData(encodedData)
                }
                self.finishPersistenceWrite()
            }
        }
    }

    private func finishPersistenceWrite() {
        isPersistenceWriteInFlight = false
        if let pending = pendingPersistenceSnapshot {
            pendingPersistenceSnapshot = nil
            enqueuePersistenceSnapshot(pending)
            return
        }

        let completions = persistenceDrainCompletions
        persistenceDrainCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func writePersistenceFile(_ values: [DownloadRecord]) -> Data? {
        do {
            try FileManager.default.createDirectory(at: DownloadStorage.rootURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(values)
            try data.write(to: DownloadStorage.indexURL, options: .atomic)
            return data
        } catch {
            logger.error("Unable to persist downloads: \(error.localizedDescription)")
            return nil
        }
    }

    private func storePersistenceData(_ data: Data) {
        do {
            try AnyStoredData.store(
                data: data,
                ownerID: Self.persistenceOwner,
                field: Self.persistenceField,
                key: Self.persistenceKey
            )
        } catch {
            logger.error("Unable to persist downloads to the database: \(error.localizedDescription)")
        }
    }

    private func loadFileIndex() {
        guard let data = try? Data(contentsOf: DownloadStorage.indexURL),
              let stored = try? OfflineMetadataDecoder.decode([DownloadRecord].self, from: data)
        else { return }

        records = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
    }

    private func writeManifest(_ record: DownloadRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }

        try? data.write(to: DownloadStorage.manifestURL(for: record), options: .atomic)
    }

    // MARK: Legacy migration

    private func migrateLegacyDownloadsIfNeeded() {
        guard let session = Container.shared.currentUserSession(),
              let directories = try? FileManager.default.contentsOfDirectory(
                  at: URL.downloadsDirectory,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              )
        else { return }

        for directory in directories {
            let metadataURL = directory
                .appendingPathComponent("Metadata", isDirectory: true)
                .appendingPathComponent("Item.json", isDirectory: false)
            guard let data = try? Data(contentsOf: metadataURL),
                  let item = try? OfflineMetadataDecoder.decode(BaseItemDto.self, from: data),
                  let itemID = item.id,
                  [.movie, .episode].contains(item.type),
                  let mediaFile = try? FileManager.default
                      .contentsOfDirectory(
                          at: directory,
                          includingPropertiesForKeys: nil
                      )
                      .first(where: {
                          $0.lastPathComponent.hasPrefix("Media")
                              && !["strm", "m3u", "m3u8"].contains($0.pathExtension.lowercased())
                      })
            else { continue }

            let source = item.mediaSources?.first ?? MediaSourceInfo(
                container: mediaFile.pathExtension,
                id: itemID,
                name: "Legacy download"
            )
            guard let sourceID = source.id else { continue }

            let id = DownloadRecord.makeID(
                serverID: session.server.id,
                userID: session.user.id,
                itemID: itemID,
                mediaSourceID: sourceID
            )
            guard records[id] == nil else { continue }

            var record = DownloadRecord(
                serverID: session.server.id,
                userID: session.user.id,
                presentationItemID: itemID,
                mediaSourceID: sourceID,
                item: item,
                mediaSource: source,
                status: .completed
            )
            record.resolvedDownloadItemID = sourceID
            record.progress = 1
            record.mediaFilename = "media.\(mediaFile.pathExtension.isEmpty ? "bin" : mediaFile.pathExtension)"

            do {
                try DownloadStorage.createFolder(for: record)
                if let destination = DownloadStorage.mediaURL(for: record),
                   !FileManager.default.fileExists(atPath: destination.path)
                {
                    try FileManager.default.copyItem(at: mediaFile, to: destination)
                }

                let legacyImages = directory.appendingPathComponent("Images", isDirectory: true)
                if let imageFiles = try? FileManager.default.contentsOfDirectory(
                    at: legacyImages,
                    includingPropertiesForKeys: nil
                ) {
                    let imagesFolder = DownloadStorage.folderURL(for: record)
                        .appendingPathComponent("Images", isDirectory: true)
                    try FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
                    for image in imageFiles {
                        let destination = imagesFolder.appendingPathComponent(image.lastPathComponent)
                        if !FileManager.default.fileExists(atPath: destination.path) {
                            try? FileManager.default.copyItem(at: image, to: destination)
                        }
                        if image.lastPathComponent.hasPrefix("Primary") {
                            record.primaryImageFilename = image.lastPathComponent
                        } else if image.lastPathComponent.hasPrefix("Backdrop") {
                            record.backdropImageFilename = image.lastPathComponent
                        }
                    }
                }

                records[id] = record
                writeManifest(record)
            } catch {
                logger.error("Unable to migrate legacy download \(itemID): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Relaunch reconciliation

    private func reconcileBackgroundTasks() {
        backgroundSession.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self else { return }

                let knownTasks = Dictionary(grouping: tasks) { $0.taskDescription }
                var activeIDs = Set<String>()
                var restartIDs = Set<String>()

                for (optionalID, matchingTasks) in knownTasks {
                    guard let id = optionalID, var record = self.records[id] else {
                        for task in matchingTasks {
                            task.cancel()
                        }
                        continue
                    }
                    guard let task = matchingTasks.max(by: { $0.taskIdentifier < $1.taskIdentifier }) else {
                        continue
                    }

                    for staleTask in matchingTasks where staleTask.taskIdentifier != task.taskIdentifier {
                        staleTask.cancel()
                    }
                    activeIDs.insert(id)

                    guard record.status != .cancelled, record.status != .deleting else {
                        task.cancel()
                        continue
                    }
                    guard self.session(for: record)?.user.data.policy?.enableContentDownloading == true else {
                        task.cancel()
                        record.transferTaskIdentifier = nil
                        record.status = .failed
                        record.errorDescription = DownloadError.versionIsNotDownloadable.localizedDescription
                        record.updatedAt = .now
                        self.records[id] = record
                        self.taskAdapters[id]?.update(record: record)
                        continue
                    }

                    if !self.task(task, matches: record) {
                        task.cancel()
                        record.transferTaskIdentifier = nil
                        record.status = .queued
                        record.updatedAt = .now
                        self.records[id] = record
                        self.taskAdapters[id]?.update(record: record)
                        restartIDs.insert(id)
                        continue
                    }
                    record.transferTaskIdentifier = task.taskIdentifier
                    record.status = task.state == .suspended ? .paused : .downloading
                    record.updatedAt = .now
                    self.records[id] = record
                    self.taskAdapters[id]?.update(record: record)
                }

                for (id, var record) in self.records
                    where [.queued, .downloading, .finalizing].contains(record.status) && !activeIDs.contains(id)
                {
                    // A final media file may have been committed immediately
                    // before termination. Recover it rather than redownloading.
                    if let mediaURL = DownloadStorage.mediaURL(for: record),
                       FileManager.default.fileExists(atPath: mediaURL.path)
                    {
                        record.status = .completed
                        record.progress = 1
                        record.errorDescription = nil
                    } else {
                        record.status = .failed
                        record.errorDescription = "The background transfer was interrupted. Retry to continue."
                    }
                    record.transferTaskIdentifier = nil
                    record.updatedAt = .now
                    self.records[id] = record
                    self.taskAdapters[id]?.update(record: record)
                }
                self.rebuildAdapters()
                self.persist()
                for id in restartIDs {
                    self.startTransfer(recordID: id)
                }
            }
        }
    }

    private func task(_ task: URLSessionTask, matches record: DownloadRecord) -> Bool {
        guard let url = task.originalRequest?.url else { return false }

        let strategy = record.transferStrategy
            ?? DownloadSourceClassifier.inferredStrategy(
                itemIsLive: record.item.isLiveStream,
                source: record.mediaSource
            )

        switch strategy {
        case .itemDownload:
            return url.path.hasSuffix("/Items/\(record.resolvedDownloadItemID ?? "")/Download")

        case .directHTTPSource:
            return DownloadSourceClassifier.directHTTPURL(for: record.mediaSource) == url

        case .staticHTTPStream:
            guard url.path.hasSuffix("/Videos/\(record.presentationItemID)/stream"),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return false }

            return components.queryItems?.contains(where: {
                $0.name.caseInsensitiveCompare("mediaSourceId") == .orderedSame
                    && $0.value == record.mediaSourceID
            }) == true

        case nil:
            return false
        }
    }

    // MARK: Supplemental offline assets

    private func finalize(recordID: String) {
        if !pendingFinalizationRecordIDs.contains(recordID) {
            pendingFinalizationRecordIDs.append(recordID)
        }
        startPendingFinalizations()
    }

    private func startPendingFinalizations() {
        while activeFinalizationCount < Self.maximumConcurrentFinalizations,
              pendingFinalizationRecordIDs.isNotEmpty
        {
            let recordID = pendingFinalizationRecordIDs.removeFirst()
            guard let record = records[recordID], record.status == .finalizing else { continue }

            activeFinalizationCount += 1
            performFinalization(record, seriesArtworkSource: seriesArtworkSource(for: record))
        }
    }

    private func performFinalization(
        _ initialRecord: DownloadRecord,
        seriesArtworkSource: DownloadRecord?
    ) {
        Task { [weak self] in
            guard let self else { return }

            var record = initialRecord
            await self.refreshOfflineMetadata(for: &record)
            await self.downloadImages(for: &record, seriesArtworkSource: seriesArtworkSource)
            await self.downloadExternalSubtitles(for: &record)
            self.writeOfflineMetadata(record)
            let finalizedRecord = record

            await MainActor.run {
                defer { self.finishFinalization() }
                guard var current = self.records[initialRecord.id] else {
                    try? FileManager.default.removeItem(at: DownloadStorage.folderURL(for: finalizedRecord))
                    return
                }
                guard current.createdAt == finalizedRecord.createdAt else { return }
                guard current.status != .deleting else {
                    try? FileManager.default.removeItem(at: DownloadStorage.folderURL(for: finalizedRecord))
                    return
                }

                current.item = finalizedRecord.item
                current.mediaSource = finalizedRecord.mediaSource
                current.primaryImageFilename = finalizedRecord.primaryImageFilename
                current.seriesPrimaryImageFilename = finalizedRecord.seriesPrimaryImageFilename
                current.backdropImageFilename = finalizedRecord.backdropImageFilename
                current.imageFilenames = finalizedRecord.imageFilenames
                current.subtitleFilenames = finalizedRecord.subtitleFilenames
                current.status = .completed
                current.progress = 1
                current.transferTaskIdentifier = nil
                current.remainingMediaSources = nil
                current.errorDescription = nil
                current.updatedAt = .now
                self.setRecord(current)
                self.writeManifest(current)
            }
        }
    }

    private func finishFinalization() {
        activeFinalizationCount = max(0, activeFinalizationCount - 1)
        startPendingFinalizations()
    }

    private func seriesArtworkSource(for record: DownloadRecord) -> DownloadRecord? {
        guard let seriesID = record.item.seriesID else { return nil }

        let scope = SeriesDownloadScope(
            serverID: record.serverID,
            userID: record.userID,
            seriesID: seriesID
        )
        return taskAdaptersBySeries[scope]?
            .lazy
            .compactMap(\.record)
            .first { candidate in
                candidate.id != record.id
                    && candidate.seriesPrimaryImageFilename != nil
                    && DownloadStorage.seriesPrimaryImageURL(for: candidate).map {
                        FileManager.default.fileExists(atPath: $0.path)
                    } == true
            }
    }

    /// Refresh the downloadable item while the transfer still has a session.
    /// The package keeps the exact source selected for the transfer even when
    /// the item endpoint returns a different/default source ordering.
    private func refreshOfflineMetadata(for record: inout DownloadRecord) async {
        guard let session = session(for: record) else { return }

        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .ItemDetailFields
        parameters.ids = [record.presentationItemID]
        parameters.limit = 1

        let request = Paths.getItems(parameters: parameters)
        guard let response = try? await session.client.send(request),
              let refreshedItem = response.value.items?.first
        else { return }

        var item = refreshedItem
        item.mediaSourceCount = 1
        item.mediaSources = [record.mediaSource]

        if item.userData == nil {
            item.userData = record.item.userData ?? UserItemDataDto(key: record.presentationItemID)
        }
        if let progress = record.offlineProgress {
            item.userData?.playbackPositionTicks = progress.positionTicks
            item.userData?.isPlayed = progress.isPlayed
        }

        record.item = item
    }

    /// Store a portable metadata snapshot separately from the operational
    /// manifest. Transfer URLs, tokens, server paths, and provider headers are
    /// deliberately removed; the manifest retains what is required to resume.
    private func writeOfflineMetadata(_ record: DownloadRecord) {
        var item = record.item
        item.path = nil
        item.remoteTrailers = nil
        item.mediaSources = item.mediaSources?.map { source in
            var source = source
            source.encoderPath = nil
            source.liveStreamID = nil
            source.openToken = nil
            source.path = nil
            source.requiredHTTPHeaders = nil
            source.transcodingURL = nil
            return source
        }

        let destination = DownloadStorage.metadataURL(for: record)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(item)
            try data.write(to: destination, options: .atomic)
        } catch {
            logger.debug("Unable to save downloaded metadata: \(error.localizedDescription)")
        }
    }

    private func downloadImages(
        for record: inout DownloadRecord,
        seriesArtworkSource: DownloadRecord?
    ) async {
        guard let session = session(for: record), let itemID = record.item.id else { return }

        let imagesFolder = DownloadStorage.folderURL(for: record)
            .appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)

        if let sourceRecord = seriesArtworkSource,
           let filename = sourceRecord.seriesPrimaryImageFilename,
           let sourceURL = DownloadStorage.seriesPrimaryImageURL(for: sourceRecord)
        {
            let destination = imagesFolder.appendingPathComponent(filename, isDirectory: false)
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                record.seriesPrimaryImageFilename = filename
            } catch {
                logger.debug("Unable to reuse downloaded series artwork: \(error.localizedDescription)")
            }
        } else if let filename = await downloadSeriesPrimaryImage(for: record) {
            record.seriesPrimaryImageFilename = filename
        }

        let sources: [(name: String, type: ImageType, itemID: String, tag: String?, maxWidth: Int)] = [
            (
                "Primary",
                .primary,
                record.item.imageTags?[ImageType.primary.rawValue] == nil
                    ? record.item.parentPrimaryImageItemID ?? itemID
                    : itemID,
                record.item.imageTags?[ImageType.primary.rawValue] ?? record.item.parentPrimaryImageTag,
                600
            ),
            (
                "Backdrop",
                .backdrop,
                record.item.backdropImageTags?.first == nil
                    ? record.item.parentBackdropItemID ?? itemID
                    : itemID,
                record.item.backdropImageTags?.first ?? record.item.parentBackdropImageTags?.first,
                1920
            ),
            (
                "Logo",
                .logo,
                record.item.imageTags?[ImageType.logo.rawValue] == nil
                    ? record.item.parentLogoItemID ?? itemID
                    : itemID,
                record.item.imageTags?[ImageType.logo.rawValue] ?? record.item.parentLogoImageTag,
                800
            ),
            (
                "Thumb",
                .thumb,
                record.item.imageTags?[ImageType.thumb.rawValue] == nil
                    ? record.item.parentThumbItemID ?? itemID
                    : itemID,
                record.item.imageTags?[ImageType.thumb.rawValue] ?? record.item.parentThumbImageTag,
                1000
            ),
        ]

        for source in sources {
            guard let tag = source.tag else { continue }

            let parameters = Paths.GetItemImageParameters(
                maxWidth: source.maxWidth,
                tag: tag
            )
            let request = Paths.getItemImage(
                itemID: source.itemID,
                imageType: source.type.rawValue,
                parameters: parameters
            )
            guard let response = try? await session.client.download(
                for: request
            )
            else { continue }

            let ext = response.response.suggestedFilename.flatMap { URL(fileURLWithPath: $0).pathExtension }
                ?? response.response.mimeSubtype
                ?? "jpg"
            let filename = "\(source.name).\(ext)"
            let destination = imagesFolder.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.moveItem(at: response.value, to: destination)
                if source.name == "Primary" {
                    record.primaryImageFilename = filename
                } else if source.name == "Backdrop" {
                    record.backdropImageFilename = filename
                }
                var imageFilenames = record.imageFilenames ?? [:]
                imageFilenames[source.type.rawValue] = filename
                record.imageFilenames = imageFilenames
            } catch {
                logger.debug("Unable to save downloaded artwork: \(error.localizedDescription)")
            }
        }
    }

    private func downloadSeriesPrimaryImage(for record: DownloadRecord) async -> String? {
        guard record.item.type == .episode,
              let seriesID = record.item.seriesID,
              !seriesID.isEmpty,
              let session = session(for: record)
        else { return nil }

        let request = Paths.getItemImage(
            itemID: seriesID,
            imageType: ImageType.primary.rawValue,
            parameters: Paths.GetItemImageParameters(maxWidth: 600)
        )
        guard let response = try? await session.client.download(for: request) else { return nil }

        let ext = response.response.suggestedFilename.flatMap { URL(fileURLWithPath: $0).pathExtension }
            ?? response.response.mimeSubtype
            ?? "jpg"
        let filename = "SeriesPrimary.\(ext)"
        let destination = DownloadStorage.folderURL(for: record)
            .appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)

        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: response.value, to: destination)
            return filename
        } catch {
            logger.debug("Unable to save downloaded series artwork: \(error.localizedDescription)")
            return nil
        }
    }

    private func downloadExternalSubtitles(for record: inout DownloadRecord) async {
        guard let session = session(for: record),
              let routeItemID = record.resolvedDownloadItemID
        else { return }

        let streams = record.mediaSource.mediaStreams?.filter {
            $0.type == .subtitle
                && $0.isExternal == true
                && $0.isTextSubtitleStream == true
                && $0.index != nil
        } ?? []
        guard streams.isNotEmpty else { return }

        let subtitlesFolder = DownloadStorage.folderURL(for: record)
            .appendingPathComponent("Subtitles", isDirectory: true)
        try? FileManager.default.createDirectory(at: subtitlesFolder, withIntermediateDirectories: true)

        for stream in streams {
            guard let index = stream.index else { continue }

            let format = stream.codec ?? "srt"
            let request = Paths.getSubtitle(
                routeItemID: routeItemID,
                routeMediaSourceID: record.mediaSourceID,
                routeIndex: index,
                routeFormat: format
            )
            guard let text = try? await session.client.send(request).value else { continue }

            let filename = "\(index).\(format)"
            let destination = subtitlesFolder.appendingPathComponent(filename)
            do {
                try text.write(to: destination, atomically: true, encoding: .utf8)
                record.subtitleFilenames[index] = filename
            } catch {
                logger.debug("Unable to save subtitle \(index): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Offline progress

    func saveOfflineProgress(recordID: String, positionTicks: Int, isPlayed: Bool) {
        guard var record = records[recordID] else { return }

        record.offlineProgress = .init(positionTicks: positionTicks, isPlayed: isPlayed, updatedAt: .now)
        if record.item.userData == nil {
            record.item.userData = UserItemDataDto(key: record.presentationItemID)
        }
        record.item.userData?.playbackPositionTicks = positionTicks
        record.item.userData?.isPlayed = isPlayed
        record.updatedAt = .now
        setRecord(record)
        writeManifest(record)
        writeOfflineMetadata(record)
    }

    func syncOfflineProgress() {
        guard let current = Container.shared.currentUserSession() else { return }

        let pending = records.values.filter {
            $0.serverID == current.server.id && $0.userID == current.user.id && $0.offlineProgress != nil
        }

        for record in pending {
            guard let progress = record.offlineProgress else { continue }

            Task { [weak self] in
                var update = UpdateUserItemDataDto()
                update.itemID = record.presentationItemID
                update.playbackPositionTicks = progress.positionTicks
                update.isPlayed = progress.isPlayed
                update.lastPlayedDate = progress.updatedAt
                do {
                    let serverItem = try await current.client
                        .send(
                            Paths.getItem(
                                itemID: record.presentationItemID,
                                userID: record.userID
                            )
                        )
                        .value
                    if let serverUpdatedAt = serverItem.userData?.lastPlayedDate,
                       serverUpdatedAt > progress.updatedAt
                    {
                        await MainActor.run {
                            guard var latest = self?.records[record.id],
                                  latest.offlineProgress?.updatedAt == progress.updatedAt
                            else { return }

                            latest.offlineProgress = nil
                            latest.updatedAt = .now
                            self?.setRecord(latest)
                        }
                        return
                    }

                    _ = try await current.client.send(
                        Paths.updateItemUserData(
                            itemID: record.presentationItemID,
                            userID: record.userID,
                            update
                        )
                    )
                    await MainActor.run {
                        guard var latest = self?.records[record.id],
                              latest.offlineProgress?.updatedAt == progress.updatedAt
                        else { return }

                        latest.offlineProgress = nil
                        latest.updatedAt = .now
                        self?.setRecord(latest)
                    }
                } catch {
                    self?.logger.debug("Offline progress sync deferred: \(error.localizedDescription)")
                }
            }
        }
    }

    private func invalidDownloadError(
        for record: DownloadRecord,
        response: HTTPURLResponse?
    ) -> DownloadError {
        if record.transferStrategy == .directHTTPSource {
            let destination = response?.url ?? DownloadSourceClassifier.directHTTPURL(for: record.mediaSource)
            let isThirdParty = destination.map { url in
                guard let userSession = session(for: record) else { return true }

                return !isSameOrigin(url, userSession.client.configuration.url)
            } ?? true
            if isThirdParty {
                guard let statusCode = response?.statusCode else { return .invalidUpstreamResponse }

                if !(200 ..< 300).contains(statusCode) {
                    return .upstreamHTTPError(statusCode)
                }
                return .invalidUpstreamResponse
            }
        }

        if response?.statusCode == 401 || response?.statusCode == 403 {
            return .versionIsNotDownloadable
        }
        if record.transferStrategy == .directHTTPSource {
            return .invalidResponse
        }

        let isHTTPSource = record.transferStrategy == .staticHTTPStream
            || record.mediaSource.protocol == .http
            || (record.mediaSource.isRemote == true && record.mediaSource.protocol != .file)
        let statusIndicatesUnsupportedSource: Bool = {
            guard let statusCode = response?.statusCode else { return false }

            return (200 ..< 300).contains(statusCode)
                || [400, 404, 405, 415, 422].contains(statusCode)
        }()

        if isHTTPSource, response == nil || statusIndicatesUnsupportedSource {
            return .staticProxyFailed
        }
        return .invalidResponse
    }

    private func downloadFailureDiagnostic(
        response: HTTPURLResponse?,
        actualBytes: Int64?,
        reason: String
    ) -> String {
        let status = response.map { String($0.statusCode) } ?? "none"
        let mimeType = response?.mimeType
            ?? response?.value(forHTTPHeaderField: "Content-Type")
            ?? "missing"
        let expectedBytes = response.map { String($0.expectedContentLength) } ?? "unknown"
        let actualBytes = actualBytes.map(String.init) ?? "unknown"
        let finalURL = response?.url
        let endpoint = finalURL.flatMap { url -> String? in
            guard let scheme = url.scheme, let host = url.host else { return nil }

            return "\(scheme)://\(host)"
        }

        return "Reason: \(reason); HTTP: \(status); MIME: \(mimeType); bytes: \(actualBytes)/\(expectedBytes); endpoint: \(endpoint?.nilIfEmpty ?? "unknown")."
    }

    private func payloadErrorReason(at location: URL, response: HTTPURLResponse) -> String? {
        let mimeType = response.mimeType?.lowercased()
            ?? response.value(forHTTPHeaderField: "Content-Type")?.lowercased()

        if let mimeType {
            if mimeType.contains("json") {
                return "response MIME type is JSON"
            }
            if mimeType.contains("html") || mimeType.contains("xml") {
                return "response MIME type is HTML/XML"
            }
            if mimeType.hasPrefix("text/") {
                return "response MIME type is text"
            }
            if mimeType.contains("mpegurl") || mimeType.contains("m3u8") {
                return "response is a streaming playlist, not a finite media file"
            }
        }

        guard let handle = try? FileHandle(forReadingFrom: location) else {
            return "temporary response body could not be inspected"
        }

        defer { handle.closeFile() }
        let prefixData = handle.readData(ofLength: 1024)
        if prefixData.starts(with: Data("d8:announce".utf8))
            || prefixData.starts(with: Data("d13:announce-list".utf8))
        {
            return "response body is BitTorrent metadata, not a media file"
        }
        guard let prefix = String(data: prefixData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return nil }

        if prefix.hasPrefix("<!doctype html")
            || prefix.hasPrefix("<html")
            || prefix.hasPrefix("<?xml")
        {
            return "response body is an HTML/XML error document"
        }
        if (prefix.hasPrefix("{") || prefix.hasPrefix("["))
            && (prefix.contains("\"error\"")
                || prefix.contains("\"message\"")
                || prefix.contains("\"statuscode\""))
        {
            return "response body is a JSON error document"
        }
        return nil
    }

    private func isImplausiblySmallMedia(actualBytes: Int64, expectedBytes: Int64) -> Bool {
        expectedBytes >= Self.minimumComparableMediaSize
            && actualBytes < expectedBytes / Self.minimumPlausibleMediaFraction
    }

    private func reconciledExpectedBytes(
        reportedBytes: Int64,
        estimatedBytes: Int64?
    ) -> Int64? {
        guard reportedBytes > 0 else { return estimatedBytes }
        guard let estimatedBytes,
              isImplausiblySmallMedia(actualBytes: reportedBytes, expectedBytes: estimatedBytes)
        else { return reportedBytes }

        return estimatedBytes
    }

    private func logInvalidDownloadResponse(
        record: DownloadRecord,
        response: HTTPURLResponse?,
        actualBytes: Int64?,
        reason: String
    ) {
        logger.error(
            "Rejected download response: \(reason)",
            metadata: downloadResponseMetadata(
                record: record,
                response: response,
                actualBytes: actualBytes
            )
        )
    }

    private func downloadResponseMetadata(
        record: DownloadRecord,
        response: HTTPURLResponse?,
        actualBytes: Int64?
    ) -> Logger.Metadata {
        let finalURL = response?.url
        let sourceURL = record.mediaSource.path.flatMap(URL.init(string:))
        return [
            "presentationItemID": .string(record.presentationItemID),
            "mediaSourceID": .string(record.mediaSourceID),
            "mediaProtocol": .string(record.mediaSource.protocol?.rawValue ?? "unknown"),
            "transferStrategy": .string(record.transferStrategy?.rawValue ?? "legacy-unresolved"),
            "httpStatus": .stringConvertible(response?.statusCode ?? -1),
            "mimeType": .string(response?.mimeType ?? response?.value(forHTTPHeaderField: "Content-Type") ?? "missing"),
            "expectedBytes": .stringConvertible(response?.expectedContentLength ?? -1),
            "actualBytes": .stringConvertible(actualBytes ?? -1),
            "suggestedFilename": .string(response?.suggestedFilename ?? "missing"),
            "contentDisposition": .string(response?.value(forHTTPHeaderField: "Content-Disposition") ?? "missing"),
            "contentEncoding": .string(response?.value(forHTTPHeaderField: "Content-Encoding") ?? "missing"),
            "finalURLScheme": .string(finalURL?.scheme ?? "missing"),
            "finalURLHost": .string(finalURL?.host ?? "missing"),
            "itemPathExtension": .string(record.item.path.map { URL(fileURLWithPath: $0).pathExtension } ?? "missing"),
            "sourceURLScheme": .string(sourceURL?.scheme ?? "missing"),
            "sourceURLHost": .string(sourceURL?.host ?? "missing"),
        ]
    }
}

// MARK: URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let id = task.taskDescription,
              let record = records[id],
              record.transferTaskIdentifier == task.taskIdentifier,
              let sourceURL = response.url,
              let destinationURL = request.url
        else {
            completionHandler(nil)
            return
        }
        guard DownloadSourceClassifier.finiteHTTPURL(from: destinationURL.absoluteString) != nil else {
            task.cancel()
            let error: DownloadError = if ["m3u", "m3u8"].contains(destinationURL.pathExtension.lowercased()) {
                .unsupportedHLS
            } else if record.transferStrategy == .directHTTPSource {
                .invalidUpstreamResponse
            } else {
                .staticProxyFailed
            }
            fail(recordID: id, error: error)
            completionHandler(nil)
            return
        }

        var redirectedRequest = request
        if isSameOrigin(sourceURL, destinationURL) {
            if let userSession = self.session(for: record),
               isSameOrigin(destinationURL, userSession.client.configuration.url)
            {
                redirectedRequest.setValue(
                    authorizationHeader(for: userSession),
                    forHTTPHeaderField: "Authorization"
                )
            } else if record.transferStrategy == .directHTTPSource {
                applyRequiredHTTPHeaders(record.mediaSource.requiredHTTPHeaders, to: &redirectedRequest)
            }
        } else {
            // Provider and Jellyfin credentials are scoped to their original
            // origin. Cross-origin CDN redirects retain URL query signing but
            // never inherit caller-supplied headers.
            var names = Set(record.mediaSource.requiredHTTPHeaders?.keys.map { $0.lowercased() } ?? [])
            names.formUnion([
                "authorization",
                "cookie",
                "origin",
                "proxy-authorization",
                "referer",
                "x-emby-authorization",
                "x-mediabrowser-token",
            ])
            let inheritedNames = redirectedRequest.allHTTPHeaderFields?.keys.filter {
                names.contains($0.lowercased())
            } ?? []
            for name in inheritedNames {
                redirectedRequest.setValue(nil, forHTTPHeaderField: name)
            }
        }
        completionHandler(redirectedRequest)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadTask.taskDescription else { return }
        guard var record = records[id],
              record.transferTaskIdentifier == downloadTask.taskIdentifier,
              [.queued, .downloading, .paused].contains(record.status)
        else { return }

        if record.status != .paused {
            record.status = .downloading
        }
        record.bytesWritten = totalBytesWritten
        let expectedBytes = reconciledExpectedBytes(
            reportedBytes: totalBytesExpectedToWrite,
            estimatedBytes: record.expectedBytes
        )
        if let expectedBytes, expectedBytes > 0 {
            record.expectedBytes = expectedBytes
            record.progress = min(1, Double(totalBytesWritten) / Double(expectedBytes))
        }
        record.updatedAt = .now
        setProgressRecord(record)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = downloadTask.taskDescription,
              var record = records[id],
              record.transferTaskIdentifier == downloadTask.taskIdentifier
        else { return }
        guard record.status != .cancelled, record.status != .deleting else { return }

        let temporaryBytes = (try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map(Int64.init)
        guard let response = downloadTask.response as? HTTPURLResponse else {
            let reason = "response was not HTTP"
            logInvalidDownloadResponse(
                record: record,
                response: nil,
                actualBytes: temporaryBytes,
                reason: reason
            )
            fail(
                recordID: id,
                error: invalidDownloadError(for: record, response: nil),
                diagnostic: downloadFailureDiagnostic(
                    response: nil,
                    actualBytes: temporaryBytes,
                    reason: reason
                )
            )
            return
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            let reason = "HTTP status was not successful"
            logInvalidDownloadResponse(
                record: record,
                response: response,
                actualBytes: temporaryBytes,
                reason: reason
            )
            fail(
                recordID: id,
                error: invalidDownloadError(for: record, response: response),
                diagnostic: downloadFailureDiagnostic(
                    response: response,
                    actualBytes: temporaryBytes,
                    reason: reason
                )
            )
            return
        }

        if let reason = payloadErrorReason(at: location, response: response) {
            let responseError: DownloadError = reason.contains("streaming playlist")
                ? .unsupportedHLS
                : invalidDownloadError(for: record, response: response)
            logInvalidDownloadResponse(
                record: record,
                response: response,
                actualBytes: temporaryBytes,
                reason: reason
            )
            fail(
                recordID: id,
                error: responseError,
                diagnostic: downloadFailureDiagnostic(
                    response: response,
                    actualBytes: temporaryBytes,
                    reason: reason
                )
            )
            return
        }

        let pathExtension = DownloadSourceClassifier.outputExtension(
            suggestedFilename: response.suggestedFilename,
            mimeType: response.mimeType,
            source: record.mediaSource
        )
        let filename = "media.\(pathExtension)"
        let destination = DownloadStorage.folderURL(for: record).appendingPathComponent(filename)
        let staging = DownloadStorage.folderURL(for: record).appendingPathComponent("media.download")

        do {
            try DownloadStorage.createFolder(for: record)
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: staging)

            let values = try staging.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Int64(values.fileSize ?? 0)
            guard fileSize > 0 else {
                let reason = "response body was empty"
                logInvalidDownloadResponse(
                    record: record,
                    response: response,
                    actualBytes: fileSize,
                    reason: reason
                )
                try? FileManager.default.removeItem(at: staging)
                fail(
                    recordID: id,
                    error: invalidDownloadError(for: record, response: response),
                    diagnostic: downloadFailureDiagnostic(
                        response: response,
                        actualBytes: fileSize,
                        reason: reason
                    )
                )
                return
            }

            if let expectedBytes = record.expectedBytes,
               isImplausiblySmallMedia(actualBytes: fileSize, expectedBytes: expectedBytes)
            {
                let reason = "response body was implausibly small for the selected media source"
                logInvalidDownloadResponse(
                    record: record,
                    response: response,
                    actualBytes: fileSize,
                    reason: reason
                )
                try? FileManager.default.removeItem(at: staging)
                fail(
                    recordID: id,
                    error: invalidDownloadError(for: record, response: response),
                    diagnostic: downloadFailureDiagnostic(
                        response: response,
                        actualBytes: fileSize,
                        reason: reason
                    )
                )
                return
            }

            // URLSession validates transfer completion. The response length
            // can describe only a resumed range, a compressed representation,
            // or be rewritten/omitted by a reverse proxy, so an exact equality
            // requirement rejects otherwise valid media. Retain the mismatch
            // as a diagnostic while MIME/body validation protects against
            // saving a same-length HTML or JSON error document.
            if response.expectedContentLength > 0, fileSize != response.expectedContentLength {
                logger.warning(
                    "Download response length differs from the completed file",
                    metadata: downloadResponseMetadata(
                        record: record,
                        response: response,
                        actualBytes: fileSize
                    )
                )
            }

            try FileManager.default.moveItem(at: staging, to: destination)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path
            )

            record.mediaFilename = filename
            record.status = .finalizing
            record.progress = 1
            record.bytesWritten = fileSize
            record.updatedAt = .now
            DispatchQueue.main.async { [weak self] in
                self?.setRecord(record)
                self?.finalize(recordID: id)
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            let reason = "unable to commit the downloaded file: \(error.localizedDescription)"
            logInvalidDownloadResponse(
                record: record,
                response: response,
                actualBytes: temporaryBytes,
                reason: reason
            )
            DispatchQueue.main.async { [weak self] in
                self?.fail(
                    recordID: id,
                    error: error,
                    diagnostic: self?.downloadFailureDiagnostic(
                        response: response,
                        actualBytes: temporaryBytes,
                        reason: reason
                    )
                )
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let record = self.records[id],
                  record.transferTaskIdentifier == task.taskIdentifier,
                  let status = self.records[id]?.status,
                  status != .cancelled,
                  status != .deleting,
                  status != .completed,
                  status != .failed,
                  status != .finalizing
            else { return }

            let response = task.response as? HTTPURLResponse
            let destination = response?.url ?? DownloadSourceClassifier.directHTTPURL(for: record.mediaSource)
            let isDirectProvider = record.transferStrategy == .directHTTPSource
                && (destination.map {
                    guard let userSession = self.session(for: record) else { return true }

                    return !self.isSameOrigin($0, userSession.client.configuration.url)
                } ?? true)
            let reason = isDirectProvider
                ? "provider transfer failed with URL error code \((error as NSError).code)"
                : "URLSession transfer failed: \(error.localizedDescription)"
            self.logInvalidDownloadResponse(
                record: record,
                response: response,
                actualBytes: record.bytesWritten,
                reason: reason
            )
            self.fail(
                recordID: id,
                error: isDirectProvider ? DownloadError.upstreamTransportError : error,
                diagnostic: self.downloadFailureDiagnostic(
                    response: response,
                    actualBytes: record.bytesWritten,
                    reason: reason
                )
            )
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard session.configuration.identifier == Self.backgroundSessionIdentifier else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                Self.finishBackgroundSessionEvents()
                return
            }

            self.persist(after: 0) {
                DispatchQueue.main.async {
                    Self.finishBackgroundSessionEvents()
                }
            }
        }
    }

    private static func finishBackgroundSessionEvents() {
        let completion = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        completion?()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
