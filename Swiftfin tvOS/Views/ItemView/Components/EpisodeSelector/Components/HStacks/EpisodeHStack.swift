//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import JellyfinAPI
import SwiftUI

extension SeriesEpisodeSelector {

    struct LoadingEpisodeHStack: View {

        var body: some View {
            EpisodeRow(scrollDisabled: true) {
                ForEach(0 ..< 4, id: \.self) { _ in
                    SeriesEpisodeSelector.LoadingCard()
                        .disabled(true)
                        .focusable(false)
                        .episodeHStackItemFrame()
                }
            }
            .padding(.bottom, 45)
            .allowsHitTesting(false)
            .transition(.opacity.animation(.linear(duration: 0.1)))
        }
    }

    struct EpisodeHStack: View {

        @Environment(\.cinematicFocusRegionChanged)
        private var focusRegionChanged
        @Environment(\.cinematicScrollTargetRequested)
        private var scrollTargetRequested

        @ObservedObject
        var viewModel: SeriesItemViewModel

        @Binding
        var activeSeasonID: SeasonItemViewModel.ID

        @Binding
        var focusedRegion: SeriesEpisodeSelector.FocusRegion?

        @Binding
        var seasonScrollRequest: SeasonScrollRequest?

        @State
        private var snapshot = EpisodeSelectorSnapshot()

        @State
        private var requestedSeasonObjectIDs: Set<ObjectIdentifier> = []

        @State
        private var snapshotUpdateTask: Task<Void, Never>?

        @StateObject
        private var seasonObserver = SeasonChangeObserver()

        private var isWaitingForEpisodeRows: Bool {
            snapshot.rows.isEmpty && viewModel.seasons.contains { seasonViewModel in
                switch seasonViewModel.state {
                case .initial, .refreshing:
                    true
                case .content, .error:
                    false
                }
            }
        }

        // MARK: - Content View

        private func contentView(proxy: ScrollViewProxy) -> some View {
            EpisodeRow {
                ForEach(snapshot.rows) { row in
                    switch row {
                    case let .episode(entry):
                        SeriesEpisodeSelector.EpisodeCard(entry: entry) {
                            entryFocused(
                                episodeID: entry.id,
                                seasonID: entry.seasonID
                            )
                        }
                        .episodeHStackItemFrame()
                        .id(EpisodeScrollTarget.episode(entry.id))
                    case let .seasonError(entry):
                        SeriesEpisodeSelector.ErrorCard(error: entry.error) {
                            entry.viewModel.send(.refresh)
                        } onEntryFocused: {
                            entryFocused(seasonID: entry.seasonID)
                        }
                        .episodeHStackItemFrame()
                        .id(EpisodeScrollTarget.season(entry.seasonID))
                    }
                }
            }
            .onChange(of: seasonScrollRequest?.id) { _, _ in
                scrollToSeasonRequest(proxy: proxy, animated: true)
            }
            .onChange(of: snapshot.identity) { _, _ in
                DispatchQueue.main.async {
                    scrollToSeasonRequest(proxy: proxy)
                }
            }
        }

        private func loadAllInitialSeasons() {
            let currentSeasonObjectIDs = Set(viewModel.seasons.map { ObjectIdentifier($0) })
            requestedSeasonObjectIDs.formIntersection(currentSeasonObjectIDs)

            for seasonViewModel in viewModel.seasons {
                let objectID = ObjectIdentifier(seasonViewModel)

                guard seasonViewModel.state == .initial,
                      !requestedSeasonObjectIDs.contains(objectID)
                else { continue }

                requestedSeasonObjectIDs.insert(objectID)
                seasonViewModel.send(.refresh)
            }
        }

        private func rebuildSnapshot() {
            snapshot = makeSnapshot()
        }

        private func makeSnapshot() -> EpisodeSelectorSnapshot {
            var next = EpisodeSelectorSnapshot()

            for seasonViewModel in viewModel.seasons {
                switch seasonViewModel.state {
                case .content:
                    appendEpisodes(from: seasonViewModel, to: &next)
                case let .error(error):
                    appendError(error, from: seasonViewModel, to: &next)
                case .initial, .refreshing:
                    continue
                }
            }

            return next
        }

        private func appendEpisodes(
            from seasonViewModel: SeasonItemViewModel,
            to snapshot: inout EpisodeSelectorSnapshot
        ) {
            let episodes = seasonViewModel.elements.compactMap { episode -> LoadedEpisode? in
                LoadedEpisode(
                    episode: episode,
                    seasonID: seasonViewModel.id
                )
            }

            guard let firstEpisodeID = episodes.first?.id,
                  let lastEpisodeID = episodes.last?.id
            else { return }

            snapshot.rows.append(contentsOf: episodes.map(EpisodeSelectorRowEntry.episode))
            snapshot.seasonTargets[seasonViewModel.id] = SeasonTargets(
                firstEpisodeID: firstEpisodeID,
                lastEpisodeID: lastEpisodeID
            )

            for episode in episodes {
                snapshot.episodeToSeason[episode.id] = episode.seasonID
            }
        }

        private func appendError(
            _ error: ErrorMessage,
            from seasonViewModel: SeasonItemViewModel,
            to snapshot: inout EpisodeSelectorSnapshot
        ) {
            let id = seasonViewModel.id ?? "error-\(ObjectIdentifier(seasonViewModel))"

            let loadedError = LoadedSeasonError(
                id: id,
                seasonID: seasonViewModel.id,
                viewModel: seasonViewModel,
                error: error
            )

            snapshot.rows.append(.seasonError(loadedError))
            snapshot.errorSeasonIDs.insert(seasonViewModel.id)
        }

        private func scheduleSnapshotUpdate() {
            snapshotUpdateTask?.cancel()
            snapshotUpdateTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                } catch {
                    return
                }

                await MainActor.run {
                    rebuildSnapshot()
                }
            }
        }

        private func entryFocused(
            episodeID: LoadedEpisode.ID? = nil,
            seasonID providedSeasonID: SeasonItemViewModel.ID
        ) {
            scrollTargetRequested(.episodeSelector)

            if focusedRegion != .episodes {
                focusedRegion = .episodes
                focusRegionChanged(.belowHeader)
            }

            let seasonID = episodeID.flatMap { snapshot.episodeToSeason[$0] } ?? providedSeasonID

            if activeSeasonID != seasonID {
                activeSeasonID = seasonID
            }
        }

        private func scrollToSeasonRequest(
            proxy: ScrollViewProxy,
            animated: Bool = false
        ) {
            guard let seasonScrollRequest,
                  let target = scrollTarget(for: seasonScrollRequest)
            else { return }

            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(target, anchor: seasonScrollRequest.reason.anchor)
                }
            } else {
                proxy.scrollTo(target, anchor: seasonScrollRequest.reason.anchor)
            }

            self.seasonScrollRequest = nil
        }

        private func scrollTarget(for request: SeasonScrollRequest) -> EpisodeScrollTarget? {
            guard let targets = snapshot.seasonTargets[request.seasonID] else {
                if snapshot.errorSeasonIDs.contains(request.seasonID) {
                    return .season(request.seasonID)
                }

                return nil
            }

            switch request.reason {
            case .focusedFromNextSeason:
                return .episode(targets.lastEpisodeID)
            case let .initialPlayButtonItem(episodeID):
                if let episodeID,
                   snapshot.episodeToSeason[episodeID] == request.seasonID
                {
                    return .episode(episodeID)
                }

                return .episode(targets.firstEpisodeID)
            case .focusedFromPreviousSeason, .selected:
                return .episode(targets.firstEpisodeID)
            }
        }

        // MARK: - Body

        var body: some View {
            Group {
                if isWaitingForEpisodeRows {
                    LoadingEpisodeHStack()
                } else {
                    ZStack(alignment: .topLeading) {
                        PlaceholderHStack()

                        ScrollViewReader { proxy in
                            contentView(proxy: proxy)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .transition(.opacity.animation(.linear(duration: 0.1)))
                    .padding(.bottom, 45)
                    .focusSection()
                }
            }
            .onFirstAppear {
                seasonObserver.observe(Array(viewModel.seasons))
                loadAllInitialSeasons()
                rebuildSnapshot()
            }
            .onChange(of: viewModel.seasons.map(\.id)) { _, _ in
                seasonObserver.observe(Array(viewModel.seasons))
                loadAllInitialSeasons()
                rebuildSnapshot()
            }
            .onReceive(seasonObserver.changes) { _ in
                loadAllInitialSeasons()
                scheduleSnapshotUpdate()
            }
            .onDisappear {
                snapshotUpdateTask?.cancel()
            }
        }
    }
}

@MainActor
private final class SeasonChangeObserver: ObservableObject {

    let changes = PassthroughSubject<Void, Never>()

    private var observedSeasonObjectIDs: [ObjectIdentifier] = []
    private var cancellable: AnyCancellable?

    func observe(_ seasons: [SeasonItemViewModel]) {
        let seasonObjectIDs = seasons.map { ObjectIdentifier($0) }

        guard seasonObjectIDs != observedSeasonObjectIDs else { return }

        observedSeasonObjectIDs = seasonObjectIDs

        guard seasons.isNotEmpty else {
            cancellable = nil
            return
        }

        cancellable = Publishers.MergeMany(seasons.map { season in
            season.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        })
        .sink { [changes] _ in
            changes.send()
        }
    }
}

private enum EpisodeScrollTarget: Hashable {
    case episode(SeriesEpisodeSelector.LoadedEpisode.ID)
    case season(SeasonItemViewModel.ID)
}

private struct PlaceholderHStack: View {

    var body: some View {
        EpisodeRow(scrollDisabled: true) {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear
                    .posterStyle(.landscape)

                Color.clear
                    .frame(height: 110)
            }
            .episodeHStackItemFrame()
        }
        .opacity(0)
        .allowsHitTesting(false)
        .focusable(false)
        .accessibilityHidden(true)
    }
}

private struct EpisodeRow<Content: View>: View {

    private let columnCount: CGFloat = 4
    private let horizontalPadding = EdgeInsets.edgePadding
    private let itemSpacing: CGFloat = 40

    var scrollDisabled = false
    let content: () -> Content

    @State
    private var contentSize: CGSize = .zero

    private var itemWidth: CGFloat {
        let availableWidth = contentSize.width > 0 ? contentSize.width : UIScreen.main.bounds.width
        let width = (
            availableWidth - horizontalPadding * 2 - itemSpacing * (columnCount - 1)
        ) / columnCount

        return max(width, 1)
    }

    init(
        scrollDisabled: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.scrollDisabled = scrollDisabled
        self.content = content
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: itemSpacing) {
                content()
            }
            .scrollTargetLayout()
            .padding(.horizontal, horizontalPadding)
            .environment(\.episodeRowItemWidth, itemWidth)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .scrollTargetBehavior(.viewAligned)
        .scrollDisabled(scrollDisabled)
        .trackingSize($contentSize)
    }
}

private extension SeriesEpisodeSelector.EpisodeSelectorSnapshot {

    var identity: Identity {
        Identity(
            rowIDs: rows.map(\.id)
        )
    }

    struct Identity: Equatable {

        let rowIDs: [String]
    }
}

private extension View {

    func episodeHStackItemFrame() -> some View {
        modifier(EpisodeHStackItemFrame())
    }
}

private struct EpisodeHStackItemFrame: ViewModifier {

    @Environment(\.episodeRowItemWidth)
    private var itemWidth

    func body(content: Content) -> some View {
        content.frame(width: itemWidth)
    }
}

private extension EnvironmentValues {

    @Entry
    var episodeRowItemWidth: CGFloat = 380
}
