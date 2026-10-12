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

    @MainActor
    struct EpisodeHStack: View {

        @ObservedObject
        var viewModel: SeriesItemViewModel

        @Binding
        var selection: SeasonItemViewModel.ID?
        var episodeAction: ((BaseItemDto) -> Void)?
        var focusItem: BaseItemDto?
        var maximumRailHeight: CGFloat?
        var scrollsToSelection = true

        @State
        private var railSize: CGSize = .zero
        @State
        private var scrollPosition: EpisodeScrollTarget?
        @State
        private var pendingProgrammaticScroll: EpisodeScrollTarget?
        @State
        private var isUpdatingSelectionFromScroll = false
        @State
        private var didScrollToPlayButtonItem = false
        @State
        private var snapshot = EpisodeRailSnapshot()
        @StateObject
        private var seasonObserver = SeasonChangeObserver()

        private var columnCount: CGFloat {
            if UIDevice.isPhone {
                return 1.5
            }

            return EpisodeCardLayout.iPadColumnCount
        }

        private var railWidth: CGFloat {
            railSize.width > 0 ? railSize.width : UIScreen.main.bounds.width
        }

        private var unconstrainedItemWidth: CGFloat {
            EpisodeCardLayout.itemWidth(for: railWidth, columns: columnCount)
        }

        private var itemWidth: CGFloat {
            guard let maximumRailHeight else { return unconstrainedItemWidth }

            let maximumWidth = max(
                1,
                (maximumRailHeight - EpisodeCardLayout.footerHeight + EpisodeCardLayout.fadeOverlap)
                    * EpisodeCardLayout.artworkAspectRatio
            )
            return min(unconstrainedItemWidth, maximumWidth)
        }

        private var railHeight: CGFloat {
            min(
                EpisodeCardLayout.height(for: itemWidth),
                maximumRailHeight ?? .greatestFiniteMagnitude
            )
        }

        private func scroll(to seasonID: SeasonItemViewModel.ID) {
            guard let target = snapshot.firstTargetBySeasonID[seasonID] else { return }

            requestScroll(to: target)
        }

        private func requestScroll(to target: EpisodeScrollTarget) {
            scrollPosition = target
            pendingProgrammaticScroll = target
        }

        private func rebuildSnapshot() {
            let newSnapshot = EpisodeRailSnapshot(seasons: Array(viewModel.seasons))

            if snapshot.hasLoadingEntries {
                withAnimation(PosterLoadingPlaceholder.transitionAnimation) {
                    snapshot = newSnapshot
                }
            } else {
                snapshot = newSnapshot
            }

            DispatchQueue.main.async {
                scrollToPlayButtonItemIfReady()
            }
        }

        private func scrollToPlayButtonItemIfReady() {
            guard !didScrollToPlayButtonItem,
                  let playButtonItem = focusItem ?? viewModel.playButtonItem
            else { return }
            guard let episodeID = playButtonItem.id else { return }

            let preferredTarget = EpisodeScrollTarget.episode(
                seasonID: viewModel.selectorSeasonID(for: playButtonItem),
                episodeID: episodeID
            )

            let target = if snapshot.targets.contains(preferredTarget) {
                preferredTarget
            } else {
                // PlaybackInfo can omit the season ID even when the episode
                // itself is present in the rail. The episode ID is unique in
                // this snapshot, so it is a safe fallback scroll target.
                snapshot.targets.first { target in
                    if case let .episode(_, candidateEpisodeID) = target {
                        return candidateEpisodeID == episodeID
                    }
                    return false
                }
            }

            guard let target else { return }

            didScrollToPlayButtonItem = true
            requestScroll(to: target)
        }

        private var contentView: some View {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: EpisodeCardLayout.itemSpacing) {
                        ForEach(snapshot.entries) { entry in
                            EpisodeRailItem(
                                entry: entry,
                                itemWidth: itemWidth,
                                railHeight: railHeight,
                                episodeAction: episodeAction,
                                currentItemID: focusItem?.id
                            )
                            .id(entry.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, EdgeInsets.edgePadding)
                }
                .backport
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
                .scrollPosition(id: $scrollPosition, anchor: .leading)
                .onChange(of: selection) { _, newValue in
                    guard scrollsToSelection else { return }
                    guard let newValue else { return }
                    guard !isUpdatingSelectionFromScroll else {
                        isUpdatingSelectionFromScroll = false
                        return
                    }

                    scroll(to: newValue)
                }
                .onChange(of: scrollPosition) { _, newValue in
                    guard let seasonID = newValue?.seasonID, seasonID != selection else { return }

                    isUpdatingSelectionFromScroll = true
                    selection = seasonID
                }
                .onChange(of: pendingProgrammaticScroll) { _, target in
                    guard let target else { return }

                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            scrollProxy.scrollTo(target, anchor: .center)
                        }
                        if pendingProgrammaticScroll == target {
                            pendingProgrammaticScroll = nil
                        }
                    }
                }
                .onFirstAppear {
                    seasonObserver.observe(Array(viewModel.seasons))
                    rebuildSnapshot()
                }
                .onChange(of: viewModel.seasons.map { ObjectIdentifier($0) }) { _, _ in
                    seasonObserver.observe(Array(viewModel.seasons))
                    rebuildSnapshot()
                }
                .onChange(of: viewModel.playButtonItem?.id) { _, _ in
                    scrollToPlayButtonItemIfReady()
                }
                .onChange(of: focusItem?.id) { _, _ in
                    didScrollToPlayButtonItem = false
                    scrollToPlayButtonItemIfReady()
                }
                .onReceive(
                    seasonObserver.changes
                        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
                ) { _ in
                    rebuildSnapshot()
                }
                .frame(height: railHeight)
                .trackingSize($railSize)
            }
        }

        var body: some View {
            contentView
        }
    }

    private enum EpisodeScrollTarget: Hashable {
        case episode(seasonID: SeasonItemViewModel.ID, episodeID: String)
        case season(SeasonItemViewModel.ID)

        var seasonID: SeasonItemViewModel.ID {
            switch self {
            case let .episode(seasonID, _), let .season(seasonID):
                seasonID
            }
        }
    }

    private enum EpisodeRailEntry: Identifiable {
        case episode(seasonID: SeasonItemViewModel.ID, episode: BaseItemDto)
        case empty(seasonID: SeasonItemViewModel.ID)
        case error(
            seasonID: SeasonItemViewModel.ID,
            viewModel: SeasonItemViewModel,
            error: ErrorMessage
        )
        case loading(seasonID: SeasonItemViewModel.ID)

        var id: EpisodeScrollTarget {
            switch self {
            case let .episode(seasonID, episode):
                guard let episodeID = episode.id else { return .season(seasonID) }

                return .episode(
                    seasonID: seasonID,
                    episodeID: episodeID
                )

            case let .empty(seasonID), let .loading(seasonID):
                return .season(seasonID)

            case let .error(seasonID, _, _):
                return .season(seasonID)
            }
        }
    }

    @MainActor
    private struct EpisodeRailSnapshot {

        var entries: [EpisodeRailEntry] = []
        var firstTargetBySeasonID: [SeasonItemViewModel.ID: EpisodeScrollTarget] = [:]
        var targets: Set<EpisodeScrollTarget> = []

        var hasLoadingEntries: Bool {
            entries.contains { entry in
                if case .loading = entry {
                    true
                } else {
                    false
                }
            }
        }

        init(seasons: [SeasonItemViewModel] = []) {
            for seasonViewModel in seasons {
                append(seasonViewModel)
            }
        }

        private mutating func append(_ seasonViewModel: SeasonItemViewModel) {
            switch seasonViewModel.state {
            case .content:
                appendEpisodes(from: seasonViewModel)

            case let .error(error):
                append(
                    .error(
                        seasonID: seasonViewModel.id,
                        viewModel: seasonViewModel,
                        error: error
                    ),
                    for: seasonViewModel.id
                )

            case .initial, .refreshing:
                append(.loading(seasonID: seasonViewModel.id), for: seasonViewModel.id)
            }
        }

        private mutating func appendEpisodes(from seasonViewModel: SeasonItemViewModel) {
            var firstTarget: EpisodeScrollTarget?

            for episode in seasonViewModel.items {
                guard episode.id != nil else { continue }

                let entry = EpisodeRailEntry.episode(
                    seasonID: seasonViewModel.id,
                    episode: episode
                )

                guard targets.insert(entry.id).inserted else { continue }

                entries.append(entry)
                firstTarget = firstTarget ?? entry.id
            }

            if let firstTarget {
                firstTargetBySeasonID[seasonViewModel.id] = firstTarget
            } else {
                append(.empty(seasonID: seasonViewModel.id), for: seasonViewModel.id)
            }
        }

        private mutating func append(
            _ entry: EpisodeRailEntry,
            for seasonID: SeasonItemViewModel.ID
        ) {
            entries.append(entry)
            targets.insert(entry.id)
            firstTargetBySeasonID[seasonID] = entry.id
        }
    }

    @MainActor
    private struct EpisodeRailItem: View {

        let entry: EpisodeRailEntry
        let itemWidth: CGFloat
        let railHeight: CGFloat
        let episodeAction: ((BaseItemDto) -> Void)?
        let currentItemID: String?

        var body: some View {
            Group {
                switch entry {
                case let .episode(_, episode):
                    SeriesEpisodeSelector.EpisodeCard(
                        episode: episode,
                        action: episodeAction,
                        isCurrent: episode.id == currentItemID
                    )
                    .frame(width: itemWidth, height: railHeight, alignment: .top)

                case .empty:
                    SeriesEpisodeSelector.EmptyCard()
                        .frame(width: itemWidth, height: railHeight, alignment: .top)

                case let .error(_, viewModel, error):
                    SeriesEpisodeSelector.ErrorCard(error: error) {
                        viewModel.send(.refresh)
                    }
                    .frame(width: itemWidth, height: railHeight, alignment: .top)

                case .loading:
                    SeriesEpisodeSelector.LoadingCard()
                        .frame(width: itemWidth, height: railHeight, alignment: .top)
                }
            }
            .transition(.opacity)
        }
    }

    struct EmptyHStack: View {

        var body: some View {
            let availableWidth = UIScreen.main.bounds.width
            let columns: CGFloat = UIDevice.isPhone ? 1.5 : EpisodeCardLayout.iPadColumnCount
            let itemWidth = EpisodeCardLayout.itemWidth(for: availableWidth, columns: columns)
            let railHeight = EpisodeCardLayout.railHeight(for: availableWidth, columns: columns)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: EpisodeCardLayout.itemSpacing) {
                    SeriesEpisodeSelector.EmptyCard()
                        .frame(width: itemWidth, height: railHeight, alignment: .top)
                }
                .padding(.horizontal, EdgeInsets.edgePadding)
            }
            .scrollDisabled(true)
            .frame(height: railHeight)
        }
    }

    // TODO: better refresh design
    struct ErrorHStack: View {

        @ObservedObject
        var viewModel: SeasonItemViewModel

        let error: ErrorMessage

        var body: some View {
            let availableWidth = UIScreen.main.bounds.width
            let columns: CGFloat = UIDevice.isPhone ? 1.5 : EpisodeCardLayout.iPadColumnCount
            let itemWidth = EpisodeCardLayout.itemWidth(for: availableWidth, columns: columns)
            let railHeight = EpisodeCardLayout.railHeight(for: availableWidth, columns: columns)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: EpisodeCardLayout.itemSpacing) {
                    SeriesEpisodeSelector.ErrorCard(error: error) {
                        viewModel.send(.refresh)
                    }
                    .frame(width: itemWidth, height: railHeight, alignment: .top)
                }
                .padding(.horizontal, EdgeInsets.edgePadding)
            }
            .scrollDisabled(true)
            .frame(height: railHeight)
        }
    }

    struct LoadingHStack: View {

        @State
        private var railSize: CGSize = .zero

        private var columnCount: CGFloat {
            if UIDevice.isPhone {
                return 1.5
            }

            return EpisodeCardLayout.iPadColumnCount
        }

        private var railWidth: CGFloat {
            railSize.width > 0 ? railSize.width : UIScreen.main.bounds.width
        }

        private var itemWidth: CGFloat {
            EpisodeCardLayout.itemWidth(for: railWidth, columns: columnCount)
        }

        private var railHeight: CGFloat {
            EpisodeCardLayout.height(for: itemWidth)
        }

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: EpisodeCardLayout.itemSpacing) {
                    ForEach(0 ..< 5, id: \.self) { _ in
                        SeriesEpisodeSelector.LoadingCard()
                            .frame(width: itemWidth, height: railHeight, alignment: .top)
                    }
                }
                .padding(.horizontal, EdgeInsets.edgePadding)
            }
            .scrollDisabled(true)
            .frame(height: railHeight)
            .trackingSize($railSize)
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

        cancellable = Publishers.MergeMany(seasons.map { seasonViewModel in
            seasonViewModel.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        })
        .sink { [changes] _ in
            changes.send()
        }
    }
}
