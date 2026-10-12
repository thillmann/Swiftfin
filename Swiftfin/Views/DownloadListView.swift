//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftUI

fileprivate enum DownloadGrouping {

    static func seriesName(for task: DownloadTask) -> String {
        guard let name = task.item.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return L10n.unknown }
        return name
    }

    static func seriesID(for task: DownloadTask, title: String) -> String {
        if let seriesID = task.item.seriesID, !seriesID.isEmpty {
            return "id:\(seriesID)"
        }
        if title != L10n.unknown {
            let normalizedTitle = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return "name:\(normalizedTitle)"
        }
        return "episode:\(task.item.id ?? task.id)"
    }

    static func episodeSort(_ lhs: DownloadTask, _ rhs: DownloadTask) -> Bool {
        let leftIndexes = lhs.item.parentIndexNumber.flatMap { season in
            lhs.item.indexNumber.map { (season, $0) }
        }
        let rightIndexes = rhs.item.parentIndexNumber.flatMap { season in
            rhs.item.indexNumber.map { (season, $0) }
        }
        switch (leftIndexes, rightIndexes) {
        case let (left?, right?) where left != right:
            if left.0 != right.0 { return left.0 < right.0 }
            return left.1 < right.1
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            let comparison = lhs.item.displayTitle.localizedStandardCompare(rhs.item.displayTitle)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.id < rhs.id
        }
    }
}

struct DownloadListView: View {

    @ObservedObject
    var viewModel: DownloadListViewModel

    @State
    private var selectedSeries: DownloadLibraryItem?

    var body: some View {
        ZStack {
            Color.systemBackground
                .ignoresSafeArea()

            if movieTasks.isEmpty, seriesItems.isEmpty {
                ContentUnavailableView(L10n.downloads, systemImage: "arrow.down")
            } else {
                List {
                    if movieTasks.isNotEmpty {
                        Section(L10n.movies) {
                            ForEach(movieTasks) { task in
                                DownloadMovieRow(downloadTask: task)
                            }
                        }
                    }

                    if seriesItems.isNotEmpty {
                        Section(L10n.tvShowsCapitalized) {
                            ForEach(seriesItems) { item in
                                DownloadSeriesRow(item: item) {
                                    selectedSeries = item
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(L10n.downloads)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSeries) { item in
            DownloadedSeriesView(
                seriesKey: item.seriesKey,
                seriesID: item.tasks.first?.item.seriesID,
                title: item.title
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }

    private var movieTasks: [DownloadTask] {
        viewModel.items
            .filter { $0.item.type == .movie }
            .sorted {
                let comparison = $0.item.displayTitle.localizedStandardCompare($1.item.displayTitle)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return $0.id < $1.id
            }
    }

    private var seriesItems: [DownloadLibraryItem] {
        var episodeGroups: [String: (title: String, items: [DownloadTask])] = [:]

        for task in viewModel.items where task.item.type == .episode {
            let title = DownloadGrouping.seriesName(for: task)
            let key = DownloadGrouping.seriesID(for: task, title: title)
            var group = episodeGroups[key] ?? (title, [])
            group.items.append(task)
            episodeGroups[key] = group
        }

        return episodeGroups.map { key, group in
            DownloadLibraryItem(
                id: "series:\(key)",
                title: group.title,
                tasks: group.items.sorted(by: DownloadGrouping.episodeSort),
                seriesKey: key
            )
        }.sorted {
            let titleComparison = $0.title.localizedStandardCompare($1.title)
            if titleComparison != .orderedSame { return titleComparison == .orderedAscending }
            return $0.id < $1.id
        }
    }

    fileprivate struct DownloadLibraryItem: Identifiable {

        let id: String
        let title: String
        let tasks: [DownloadTask]
        let seriesKey: String

        var posterSources: [ImageSource] {
            let localSeriesPoster = tasks.lazy
                .compactMap(\.record)
                .compactMap(DownloadStorage.seriesPrimaryImageURL(for:))
                .first
            let localEpisodePoster = tasks.first?.record.flatMap {
                DownloadStorage.imageURL(for: $0, type: .primary)
            }
            var sources = [
                ImageSource(url: localSeriesPoster),
                ImageSource(url: localEpisodePoster),
            ]
            if let task = tasks.first {
                sources.append(task.item.seriesImageSource(.primary, maxWidth: 240, quality: 90))
            }
            return sources.compacted(using: \.url)
        }
    }
}

extension DownloadListView {

    private struct DownloadMovieRow: View {

        @Injected(\.downloadManager)
        private var downloadManager

        @Router
        private var router

        @ObservedObject
        var downloadTask: DownloadTask

        private var artworkSources: [ImageSource] {
            let localBackdrop = downloadTask.record.flatMap {
                DownloadStorage.imageURL(for: $0, type: .backdrop)
            }
            let localPrimary = downloadTask.record.flatMap {
                DownloadStorage.imageURL(for: $0, type: .primary)
            }
            return [
                ImageSource(url: localBackdrop),
                ImageSource(url: localPrimary),
            ].compacted(using: \.url)
                + downloadTask.item.landscapeImageSources(maxWidth: 360, quality: 90)
        }

        private var actionTitle: String {
            switch downloadTask.state {
            case .complete:
                L10n.removeDownload
            case .downloading, .paused, .resolving:
                L10n.stopDownload
            case .error:
                L10n.retryDownload
            case .cancelled, .ready:
                L10n.download
            }
        }

        var body: some View {
            HStack(spacing: 16) {
                Button(action: showDetails) {
                    HStack(spacing: 16) {
                        ImageView(artworkSources)
                            .image { image in
                                image.scaledToFill()
                            }
                            .failure {
                                Color.secondarySystemFill
                            }
                            .aspectRatio(16 / 9, contentMode: .fill)
                            .frame(width: 112, height: 68)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(downloadTask.item.displayTitle)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)

                            metadata

                            if downloadTask.state.isInProgress {
                                Text(downloadTask.transferProgressText)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                statusControl
            }
            .frame(minHeight: 92)
            .contextMenu {
                Button(L10n.details, systemImage: "info.circle", action: showDetails)
                Button(
                    actionTitle,
                    systemImage: actionIcon,
                    role: downloadTask.state.isComplete ? .destructive : nil,
                    action: performDownloadAction
                )
            }
        }

        @ViewBuilder
        private var metadata: some View {
            DotHStack {
                if let productionYear = downloadTask.item.premiereDateYear {
                    Text(productionYear)
                }
                if let runtime = downloadTask.item.runTimeLabel {
                    Text(runtime)
                }
                if let fileSize = downloadTask.expectedFileSizeText {
                    Text(fileSize)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        @ViewBuilder
        private var statusControl: some View {
            if case .complete = downloadTask.state {
                Menu {
                    Button(L10n.removeDownload, systemImage: "trash", role: .destructive) {
                        downloadManager.delete(task: downloadTask)
                    }
                } label: {
                    DownloadStatusIndicator(state: .complete)
                }
            } else {
                DownloadStatusControl(state: downloadTask.state.controlState) {
                    performDownloadAction()
                }
                .accessibilityLabel(actionTitle)
            }
        }

        private var actionIcon: String {
            switch downloadTask.state {
            case .complete:
                "trash"
            case .downloading, .paused, .resolving:
                "stop.fill"
            case .error:
                "arrow.clockwise"
            case .cancelled, .ready:
                "arrow.down"
            }
        }

        private func showDetails() {
            if case .complete = downloadTask.state,
               let record = downloadTask.record
            {
                router.route(to: .downloadedItem(record: record))
            } else {
                router.route(to: .item(item: downloadTask.item))
            }
        }

        private func performDownloadAction() {
            switch downloadTask.state {
            case .complete:
                downloadManager.delete(task: downloadTask)
            case .downloading, .paused, .resolving:
                downloadManager.cancel(task: downloadTask)
            case .error, .cancelled:
                downloadManager.retry(task: downloadTask)
            case .ready:
                downloadManager.download(task: downloadTask)
            }
        }
    }

    private struct DownloadSeriesRow: View {

        @Injected(\.downloadManager)
        private var downloadManager

        @Router
        private var router

        @State
        private var aggregateRevision = 0

        let item: DownloadLibraryItem
        let action: () -> Void

        private var summary: DownloadManager.DownloadSummary {
            _ = aggregateRevision
            return downloadManager.summary(for: item.tasks.map(\.item))
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 16) {
                    ImageView(item.posterSources)
                        .image { image in
                            image.scaledToFill()
                        }
                        .failure {
                            Color.secondarySystemFill
                        }
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .frame(width: 52, height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(verbatim: "\(item.tasks.count) \(L10n.episodes)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if summary.hasDownloads {
                        DownloadStatusIndicator(state: summary.controlState, showsStopWhenActive: false)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 94)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onReceive(downloadManager.aggregateUpdates) {
                aggregateRevision &+= 1
            }
            .contextMenu {
                Button(L10n.details, systemImage: "info.circle", action: showDetails)
            }
            .accessibilityAction(named: L10n.details, showDetails)
        }

        private func showDetails() {
            guard let seriesID = item.tasks.first?.item.seriesID else { return }
            router.route(
                to: .item(
                    item: BaseItemDto(
                        id: seriesID,
                        name: item.title,
                        type: .series
                    )
                )
            )
        }
    }
}

struct DownloadedSeriesView: View {

    @ObservedObject
    private var downloadManager = Container.shared.downloadManager()

    let seriesKey: String
    let seriesID: String?
    let title: String

    @StateObject
    private var seriesViewModel: SeriesItemViewModel

    @MainActor
    init(seriesKey: String, seriesID: String?, title: String) {
        self.seriesKey = seriesKey
        self.seriesID = seriesID
        self.title = title
        self._seriesViewModel = StateObject(
            wrappedValue: SeriesItemViewModel(
                item: BaseItemDto(id: seriesID, name: title, type: .series)
            )
        )
    }

    private var episodes: [DownloadTask] {
        downloadManager.downloadedItems()
            .filter { task in
                guard task.item.type == .episode else { return false }
                let seriesTitle = DownloadGrouping.seriesName(for: task)
                return DownloadGrouping.seriesID(for: task, title: seriesTitle) == seriesKey
            }
            .sorted(by: DownloadGrouping.episodeSort)
    }

    var body: some View {
        SeriesDownloadPickerView(
            viewModel: seriesViewModel,
            fallbackEpisodes: episodes.map(\.item)
        )
    }
}
