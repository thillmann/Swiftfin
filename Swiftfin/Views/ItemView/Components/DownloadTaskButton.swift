//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

enum DownloadControlState: Equatable {
    case available
    case resolving
    case active(Double)
    case complete
    case failed
}

struct DownloadStatusIndicator: View {

    @Default(.accentColor)
    private var accentColor

    @Environment(\.colorScheme)
    private var colorScheme

    let state: DownloadControlState
    var size: CGFloat = 34
    var showsStopWhenActive = true
    var showsBackground = true
    var isMonochrome = false

    private var progressColor: Color {
        isMonochrome ? .primary : accentColor
    }

    private var completeBackgroundColor: Color {
        isMonochrome ? .primary : accentColor
    }

    private var completeForegroundColor: Color {
        if isMonochrome {
            colorScheme == .dark ? .black : .white
        } else {
            accentColor.overlayColor
        }
    }

    private var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    private var isComplete: Bool {
        state == .complete
    }

    private var activeProgress: Double {
        if case let .active(progress) = state {
            return min(max(progress, 0.01), 1)
        }
        return isComplete ? 1 : 0.01
    }

    var body: some View {
        ZStack {
            if showsBackground {
                Circle()
                    .fill(Color.secondary.opacity(0.16))

                Circle()
                    .fill(completeBackgroundColor)
                    .opacity(isComplete ? 1 : 0)
            }

            Circle()
                .stroke(Color.secondary.opacity(0.24), lineWidth: 3)
                .padding(2)
                .opacity(isActive ? 1 : 0)

            Circle()
                .trim(from: 0, to: activeProgress)
                .stroke(progressColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2)
                .opacity(isActive ? 1 : 0)

            switch state {
            case .available:
                Image(systemName: "arrow.down")
                    .foregroundStyle(.primary)
            case .resolving:
                ProgressView()
                    .controlSize(.small)
                    .tint(progressColor)
            case .active:
                Image(systemName: showsStopWhenActive ? "stop.fill" : "arrow.down")
                    .font(.system(size: size * 0.26, weight: .bold))
                    .foregroundStyle(progressColor)
            case .complete:
                Image(systemName: "arrow.down")
                    .foregroundStyle(completeForegroundColor)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(progressColor)
            }
        }
        .font(.system(size: size * 0.42, weight: .semibold))
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentShape(Circle())
        .animation(.spring(response: 0.36, dampingFraction: 0.78), value: state)
    }
}

struct DownloadStatusControl: View {

    let state: DownloadControlState
    var size: CGFloat = 34
    var showsStopWhenActive = true
    var showsBackground = true
    var isMonochrome = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DownloadStatusIndicator(
                state: state,
                size: size,
                showsStopWhenActive: showsStopWhenActive,
                showsBackground: showsBackground,
                isMonochrome: isMonochrome
            )
        }
        .buttonStyle(.plain)
    }
}

extension DownloadTask.State {

    var controlState: DownloadControlState {
        switch self {
        case .cancelled, .ready:
            .available
        case .complete:
            .complete
        case let .downloading(progress), let .paused(progress):
            .active(progress)
        case .error:
            .failed
        case .resolving:
            .resolving
        }
    }
}

/// Download action shared by all media sources of an item.
struct DownloadTaskButton: View {

    @ObservedObject
    private var downloadManager = Container.shared.downloadManager()

    let item: BaseItemDto
    let selection: MediaSourceSelectionIntent
    let automaticItemResolver: (() async -> BaseItemDto?)?

    init(
        item: BaseItemDto,
        selection: MediaSourceSelectionIntent,
        automaticItemResolver: (() async -> BaseItemDto?)? = nil
    ) {
        self.item = item
        self.selection = selection
        self.automaticItemResolver = automaticItemResolver
    }

    @State
    private var isRemoveConfirmationPresented = false

    @State
    private var taskRevision = 0

    private var isResolvingSource: Bool {
        downloadManager.isPreparingAutomaticDownload(for: item)
    }

    private var task: DownloadTask? {
        _ = taskRevision
        if let itemTask = downloadManager.task(for: item) {
            switch itemTask.state {
            case .complete, .downloading, .paused, .ready, .resolving:
                return itemTask
            case .cancelled, .error:
                if case .automatic = selection {
                    return itemTask
                }
            }
        }

        // Keep failures source-specific so selecting another version can
        // replace the failed attempt with a new download.
        guard case let .userSelected(mediaSource) = selection else { return nil }
        return downloadManager.task(for: item, mediaSource: mediaSource)
    }

    private var taskUpdates: AnyPublisher<Void, Never> {
        guard let task else {
            return Empty<Void, Never>(completeImmediately: false).eraseToAnyPublisher()
        }
        return task.objectWillChange.eraseToAnyPublisher()
    }

    private var isDownloadAvailable: Bool {
        switch selection {
        case let .userSelected(mediaSource):
            item.canBeDownloaded(mediaSource: mediaSource)
        case .automatic:
            automaticItemResolver != nil
                || downloadManager.automaticallySelectedDownloadSource(for: item) != nil
        }
    }

    var body: some View {
        Group {
            if isResolvingSource {
                DownloadStatusControl(
                    state: .resolving,
                    showsBackground: false,
                    isMonochrome: true
                ) {
                    downloadManager.cancelAutomaticDownloadPreparation(for: item)
                }
            } else if let task, case .complete = task.state {
                Button {
                    isRemoveConfirmationPresented = true
                } label: {
                    DownloadStatusIndicator(
                        state: .complete,
                        size: 28,
                        isMonochrome: true
                    )
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .buttonBorderShape(.circle)
                .contextMenu {
                    Button(L10n.removeDownload, systemImage: "trash", role: .destructive) {
                        downloadManager.delete(task: task)
                    }
                }
                .confirmationDialog(
                    L10n.removeDownloadConfirmation,
                    isPresented: $isRemoveConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button(L10n.removeDownload, role: .destructive) {
                        downloadManager.delete(task: task)
                    }
                    Button(L10n.cancel, role: .cancel) {}
                }
            } else if let task, case .error = task.state {
                DownloadStatusControl(
                    state: .failed,
                    showsBackground: false,
                    isMonochrome: true
                ) {
                    performAction()
                }
            } else {
                DownloadStatusControl(
                    state: task?.state.controlState ?? .available,
                    showsBackground: false,
                    isMonochrome: true
                ) {
                    performAction()
                }
                .disabled(task == nil && !isDownloadAvailable)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(L10n.download)
        .accessibilityValue(accessibilityValue)
        .onReceive(taskUpdates) {
            taskRevision &+= 1
        }
    }

    private var accessibilityValue: String {
        guard let task else { return "" }
        switch task.state {
        case .downloading, .paused:
            return task.transferProgressText
        default:
            return ""
        }
    }

    private func performAction() {
        if isResolvingSource {
            downloadManager.cancelAutomaticDownloadPreparation(for: item)
            return
        }
        if let task {
            switch task.state {
            case .paused:
                downloadManager.cancel(task: task)
            case .downloading, .resolving:
                downloadManager.cancel(task: task)
            case .cancelled, .error:
                if case .automatic = selection, automaticItemResolver != nil {
                    startDownload()
                } else {
                    downloadManager.retry(task: task)
                }
            case .ready:
                if case .automatic = selection, automaticItemResolver != nil {
                    startDownload()
                } else {
                    downloadManager.download(task: task)
                }
            default:
                break
            }
        } else {
            startDownload()
        }
    }

    private func startDownload() {
        guard !isResolvingSource else { return }
        guard case .automatic = selection, let automaticItemResolver else {
            _ = downloadManager.download(item: item, selection: selection)
            return
        }

        downloadManager.download(item: item) { item in
            await automaticItemResolver() ?? item
        }
    }
}

struct SeriesDownloadButton: View {

    @Injected(\.downloadManager)
    private var downloadManager

    @State
    private var aggregateRevision = 0

    @ObservedObject
    var viewModel: SeriesItemViewModel

    @State
    private var isPickerPresented = false

    private var summary: DownloadManager.DownloadSummary {
        _ = aggregateRevision
        guard let seriesID = viewModel.item.id else { return .empty }
        return downloadManager.summary(
            forSeriesID: seriesID,
            expectedTotalCount: expectedEpisodeCount
        )
    }

    private var expectedEpisodeCount: Int? {
        let availableSeasons = viewModel.seasons
        let counts = availableSeasons.compactMap(\.season.childCount)
        guard counts.count == availableSeasons.count, counts.isNotEmpty else { return nil }
        let total = counts.reduce(0, +)
        return total > 0 ? total : nil
    }

    private var controlState: DownloadControlState {
        if expectedEpisodeCount == nil, summary.isComplete {
            return .available
        }
        return summary.controlState
    }

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            DownloadStatusIndicator(
                state: controlState,
                showsStopWhenActive: false,
                showsBackground: false,
                isMonochrome: true
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(L10n.download)
        .accessibilityValue(summary.progress.formatted(.percent.precision(.fractionLength(0))))
        .sheet(isPresented: $isPickerPresented) {
            SeriesDownloadPickerView(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .onReceive(downloadManager.aggregateUpdates) {
            aggregateRevision &+= 1
        }
    }
}

extension DownloadManager.DownloadSummary {

    var controlState: DownloadControlState {
        if isComplete {
            return .complete
        }
        if resolvingCount > 0, progress == 0 {
            return .resolving
        }
        if isActive {
            return .active(progress)
        }
        if failedCount > 0 {
            return .failed
        }
        return .available
    }
}

struct SeriesDownloadPickerView: View {

    @Environment(\.dismiss)
    private var dismiss

    @Injected(\.downloadManager)
    private var downloadManager

    @State
    private var aggregateRevision = 0

    @ObservedObject
    var viewModel: SeriesItemViewModel

    let fallbackEpisodes: [BaseItemDto]

    init(viewModel: SeriesItemViewModel, fallbackEpisodes: [BaseItemDto] = []) {
        self.viewModel = viewModel
        self.fallbackEpisodes = fallbackEpisodes
    }

    private var remoteSeasons: [BaseItemDto] {
        viewModel.seasons.map(\.season)
    }

    private var isUsingFallbackSeasons: Bool {
        remoteSeasons.isEmpty && fallbackEpisodes.isNotEmpty
    }

    private var availableSeasons: [BaseItemDto] {
        isUsingFallbackSeasons ? fallbackSeasons : remoteSeasons
    }

    private var fallbackSeasons: [BaseItemDto] {
        Dictionary(grouping: fallbackEpisodes, by: \.parentIndexNumber)
            .map { seasonNumber, episodes in
                var season = BaseItemDto(
                    id: episodes.first?.seasonID
                        ?? "downloads-\(viewModel.item.id ?? "series")-\(seasonNumber ?? -1)",
                    name: seasonNumber.map { L10n.seasonNumber($0) } ?? L10n.unknown,
                    type: .season
                )
                season.indexNumber = seasonNumber
                season.childCount = episodes.count
                season.seriesID = viewModel.item.id
                return season
            }
            .sorted { ($0.indexNumber ?? -1) < ($1.indexNumber ?? -1) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(availableSeasons, id: \.id) { season in
                        NavigationLink {
                            SeasonDownloadPickerView(
                                seriesViewModel: viewModel,
                                season: season,
                                initialEpisodes: initialEpisodes(for: season)
                            )
                        } label: {
                            seasonRow(season)
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 88)
                    }
                }
                .padding(.horizontal, 20)
            }
            .overlay {
                if availableSeasons.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle(viewModel.item.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                    }
                    .accessibilityLabel(L10n.close)
                }
            }
        }
        .onReceive(downloadManager.aggregateUpdates) {
            aggregateRevision &+= 1
        }
    }

    private func seasonSummary(_ season: BaseItemDto) -> DownloadManager.DownloadSummary {
        _ = aggregateRevision
        if isUsingFallbackSeasons {
            return downloadManager.summary(for: fallbackEpisodes(for: season))
        }
        guard let seriesID = viewModel.item.id else { return .empty }
        return downloadManager.summary(
            forSeriesID: seriesID,
            seasonNumber: season.indexNumber,
            expectedTotalCount: season.childCount
        )
    }

    private func fallbackEpisodes(for season: BaseItemDto) -> [BaseItemDto] {
        fallbackEpisodes
            .filter { $0.parentIndexNumber == season.indexNumber }
            .sorted { ($0.indexNumber ?? -1) < ($1.indexNumber ?? -1) }
    }

    private func initialEpisodes(for season: BaseItemDto) -> [BaseItemDto] {
        if isUsingFallbackSeasons {
            return fallbackEpisodes(for: season)
        }
        guard let seasonID = season.id,
              let seasonViewModel = viewModel.seasons[id: seasonID],
              seasonViewModel.state == .content
        else { return [] }
        return Array(seasonViewModel.elements)
            .sorted { ($0.indexNumber ?? -1) < ($1.indexNumber ?? -1) }
    }

    private func fallbackSeasonImageURL(_ season: BaseItemDto) -> URL? {
        fallbackEpisodes(for: season)
            .lazy
            .compactMap { downloadManager.task(for: $0)?.record }
            .compactMap(DownloadStorage.seriesPrimaryImageURL(for:))
            .first
    }

    @ViewBuilder
    private func seasonArtwork(_ season: BaseItemDto) -> some View {
        if isUsingFallbackSeasons, let imageURL = fallbackSeasonImageURL(season) {
            ImageView(imageURL)
        } else {
            ImageView(season.portraitImageSources(maxWidth: 120))
        }
    }

    private func seasonRow(_ season: BaseItemDto) -> some View {
        let summary = seasonSummary(season)
        return HStack(spacing: 16) {
            seasonArtwork(season)
                .aspectRatio(2 / 3, contentMode: .fill)
                .frame(width: 52, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(season.displayTitle)
                .font(.title3)
                .foregroundStyle(.primary)

            Spacer()

            if summary.hasDownloads {
                DownloadStatusIndicator(state: summary.controlState, showsStopWhenActive: false)
            } else {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 106)
        .contentShape(Rectangle())
    }
}

private struct SeasonDownloadPickerView: View {

    @Injected(\.downloadManager)
    private var downloadManager

    @ObservedObject
    var seriesViewModel: SeriesItemViewModel

    let season: BaseItemDto

    @State
    private var episodes: [BaseItemDto] = []

    @State
    private var isLoading = true

    @State
    private var error: Error?

    @State
    private var aggregateRevision = 0

    init(
        seriesViewModel: SeriesItemViewModel,
        season: BaseItemDto,
        initialEpisodes: [BaseItemDto] = []
    ) {
        self.seriesViewModel = seriesViewModel
        self.season = season
        self._episodes = State(initialValue: initialEpisodes)
        self._isLoading = State(initialValue: initialEpisodes.isEmpty)
    }

    private var summary: DownloadManager.DownloadSummary {
        _ = aggregateRevision
        if episodes.isNotEmpty {
            return downloadManager.summary(for: episodes)
        }
        guard let seriesID = seriesViewModel.item.id else { return .empty }
        return downloadManager.summary(
            forSeriesID: seriesID,
            seasonNumber: season.indexNumber
        )
    }

    private var isResolvingSources: Bool {
        _ = aggregateRevision
        return episodes.contains(where: downloadManager.isPreparingAutomaticDownload(for:))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                seasonHeader

                Divider()
                    .padding(.leading, 116)

                ForEach(episodes, id: \.id) { episode in
                    DownloadEpisodeRow(
                        item: episode,
                        seriesViewModel: seriesViewModel
                    )

                    Divider()
                        .padding(.leading, 116)
                }
            }
            .padding(.horizontal, 20)
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle("\(seriesViewModel.item.displayTitle), \(season.displayTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if episodes.isEmpty {
                await loadEpisodes()
            }
        }
        .errorMessage($error)
        .onReceive(downloadManager.aggregateUpdates) {
            aggregateRevision &+= 1
        }
    }

    private var seasonHeader: some View {
        HStack(spacing: 16) {
            seasonArtwork
                .aspectRatio(2 / 3, contentMode: .fill)
                .frame(width: 52, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(season.displayTitle)
                    .font(.title3)
                if episodes.isNotEmpty {
                    Text(verbatim: "\(episodes.count) \(L10n.episodes)")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if summary.isComplete {
                Menu {
                    Button(L10n.removeDownload, systemImage: "trash", role: .destructive) {
                        downloadManager.removeDownloads(for: episodes)
                    }
                } label: {
                    DownloadStatusIndicator(state: .complete, size: 40)
                }
            } else {
                DownloadStatusControl(
                    state: isResolvingSources ? .resolving : summary.controlState,
                    size: 40
                ) {
                    performSeasonAction()
                }
                .disabled(isLoading || episodes.isEmpty)
                .accessibilityLabel(seasonActionTitle)
            }
        }
        .frame(minHeight: 106)
        .contextMenu {
            Button(seasonActionTitle, systemImage: seasonActionIcon) {
                performSeasonAction()
            }
        }
    }

    @ViewBuilder
    private var seasonArtwork: some View {
        if let imageURL = episodes
            .lazy
            .compactMap({ downloadManager.task(for: $0)?.record })
            .compactMap(DownloadStorage.seriesPrimaryImageURL(for:))
            .first
        {
            ImageView(imageURL)
        } else {
            ImageView(season.portraitImageSources(maxWidth: 120))
        }
    }

    private var seasonActionTitle: String {
        if summary.isActive { return L10n.stopDownload }
        if summary.isComplete { return L10n.removeDownload }
        if summary.failedCount > 0 { return L10n.retryDownload }
        if summary.hasDownloads { return L10n.downloadRemaining }
        return L10n.downloadSeason
    }

    private var seasonActionIcon: String {
        if summary.isActive { return "stop.fill" }
        if summary.isComplete { return "trash" }
        if summary.failedCount > 0 { return "arrow.clockwise" }
        return "arrow.down"
    }

    private func performSeasonAction() {
        if summary.isActive {
            downloadManager.cancelDownloads(for: episodes)
        } else if summary.isComplete {
            downloadManager.removeDownloads(for: episodes)
        } else {
            downloadManager.download(items: episodes) { episode in
                await seriesViewModel.episodeResolvingDownloadSources(episode)
            }
        }
    }

    @MainActor
    private func loadEpisodes() async {
        do {
            episodes = try await seriesViewModel.getEpisodesForDownload(in: season)
        } catch {
            self.error = error
        }
        isLoading = false
    }
}

private struct DownloadEpisodeRow: View {

    @Injected(\.downloadManager)
    private var downloadManager

    @State
    private var taskRevision = 0

    @State
    private var structuralRevision = 0

    let item: BaseItemDto
    @ObservedObject
    var seriesViewModel: SeriesItemViewModel

    private var isSourceResolutionActive: Bool {
        _ = structuralRevision
        return downloadManager.isPreparingAutomaticDownload(for: item)
    }

    private var task: DownloadTask? {
        _ = taskRevision
        _ = structuralRevision
        return downloadManager.task(for: item)
    }

    private var taskUpdates: AnyPublisher<Void, Never> {
        guard let task else {
            return Empty<Void, Never>(completeImmediately: false).eraseToAnyPublisher()
        }
        return task.objectWillChange.eraseToAnyPublisher()
    }

    private var controlState: DownloadControlState {
        isSourceResolutionActive ? .resolving : task?.state.controlState ?? .available
    }

    private var downloadedEpisodeImageURL: URL? {
        task?.record.flatMap { DownloadStorage.imageURL(for: $0, type: .primary) }
    }

    private var fileSizeText: String? {
        if let taskSize = task?.expectedFileSizeText {
            return taskSize
        }
        guard let bytes = downloadManager
            .automaticallySelectedDownloadSource(for: item)?
            .size
            .map(Int64.init),
            bytes > 0
        else { return nil }
        return bytes.formatted(.byteCount(style: .file))
    }

    private var actionTitle: String {
        if isSourceResolutionActive { return L10n.stopDownload }
        guard let task else { return L10n.download }
        switch task.state {
        case .complete:
            return L10n.removeDownload
        case .downloading, .paused, .resolving:
            return L10n.stopDownload
        case .error:
            return L10n.retryDownload
        case .cancelled, .ready:
            return L10n.download
        }
    }

    private var actionIcon: String {
        if isSourceResolutionActive { return "stop.fill" }
        guard let task else { return "arrow.down" }
        switch task.state {
        case .complete:
            return "trash"
        case .downloading, .paused, .resolving:
            return "stop.fill"
        case .error:
            return "arrow.clockwise"
        case .cancelled, .ready:
            return "arrow.down"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            NavigationLink {
                episodeDetailView
            } label: {
                HStack(spacing: 16) {
                    episodeArtwork
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(width: 100, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        if let indexNumber = item.indexNumber {
                            Text(L10n.episodeNumber(indexNumber))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                        Text(item.displayTitle)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if let fileSizeText {
                            Text(fileSizeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let task, case .complete = task.state {
                Menu {
                    Button(L10n.removeDownload, systemImage: "trash", role: .destructive) {
                        downloadManager.delete(task: task)
                    }
                } label: {
                    DownloadStatusIndicator(state: .complete)
                }
            } else {
                DownloadStatusControl(state: controlState) {
                    performAction()
                }
                .accessibilityLabel(actionTitle)
            }
        }
        .frame(minHeight: 94)
        .contentShape(Rectangle())
        .contextMenu {
            Button(actionTitle, systemImage: actionIcon, role: task?.state.isComplete == true ? .destructive : nil) {
                performAction()
            }
        }
        .onReceive(taskUpdates) {
            taskRevision &+= 1
        }
        .onReceive(downloadManager.$downloads.dropFirst()) { _ in
            structuralRevision &+= 1
        }
        .onReceive(downloadManager.aggregateUpdates) {
            structuralRevision &+= 1
        }
    }

    @ViewBuilder
    private var episodeDetailView: some View {
        if let task,
           case .complete = task.state,
           let record = task.record
        {
            PlatformItemView(downloadRecord: record)
        } else {
            PlatformItemView(item: item)
        }
    }

    @ViewBuilder
    private var episodeArtwork: some View {
        if let downloadedEpisodeImageURL {
            ImageView(downloadedEpisodeImageURL)
        } else {
            ImageView([item.imageSource(.primary, maxWidth: 240)])
        }
    }

    private func performAction() {
        if isSourceResolutionActive {
            downloadManager.cancelAutomaticDownloadPreparation(for: item)
            return
        }
        if let task {
            switch task.state {
            case .complete:
                downloadManager.delete(task: task)
            case .downloading, .paused, .resolving:
                downloadManager.cancel(task: task)
            case .error, .cancelled:
                startAutomaticDownload()
            case .ready:
                startAutomaticDownload()
            }
        } else {
            startAutomaticDownload()
        }
    }

    private func startAutomaticDownload() {
        downloadManager.download(item: item) { item in
            await seriesViewModel.episodeResolvingDownloadSources(item)
        }
    }
}

extension DownloadTask.State {

    var isComplete: Bool {
        if case .complete = self {
            true
        } else {
            false
        }
    }
}
