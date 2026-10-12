//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if !os(tvOS)
import CollectionHStack
#endif
import Combine
import Defaults
import Foundation
import IdentifiedCollections
import JellyfinAPI
import SwiftUI

@MainActor
class EpisodeMediaPlayerQueue: ViewModel, MediaPlayerQueue {

    weak var manager: MediaPlayerManager? {
        didSet {
            cancellables = []
            guard let manager else { return }
            manager.$playbackItem
                .sink { [weak self] newItem in
                    self?.didReceive(newItem: newItem)
                }
                .store(in: &cancellables)
        }
    }

    let displayTitle: String = L10n.episodes
    let id: String = "EpisodeMediaPlayerQueue"

    @Published
    var nextItem: MediaPlayerItemProvider? = nil
    @Published
    var previousItem: MediaPlayerItemProvider? = nil

    @Published
    var hasNextItem: Bool = false
    @Published
    var hasPreviousItem: Bool = false

    lazy var hasNextItemPublisher: Published<Bool>.Publisher = $hasNextItem
    lazy var hasPreviousItemPublisher: Published<Bool>.Publisher = $hasPreviousItem
    lazy var nextItemPublisher: Published<MediaPlayerItemProvider?>.Publisher = $nextItem
    lazy var previousItemPublisher: Published<MediaPlayerItemProvider?>.Publisher = $previousItem

    private var currentAdjacentEpisodesTask: AnyCancellable?
    private let seriesViewModel: SeriesItemViewModel

    init(episode: BaseItemDto) {
        self.seriesViewModel = SeriesItemViewModel(episode: episode)
        super.init()

        seriesViewModel.send(.refresh)
    }

    var videoPlayerBody: some PlatformView {
        EpisodeOverlay(viewModel: seriesViewModel)
    }

    private func didReceive(newItem: MediaPlayerItem?) {
        self.currentAdjacentEpisodesTask = Task {
            await MainActor.run {
                self.nextItem = nil
                self.previousItem = nil
                self.hasNextItem = false
                self.hasPreviousItem = false
            }

            try await self.getAdjacentEpisodes(for: newItem?.baseItem)
        }
        .asAnyCancellable()
    }

    private func getAdjacentEpisodes(for item: BaseItemDto?) async throws {
        guard let item else { return }
        guard let seriesID = item.seriesID, item.type == .episode else { return }

        let parameters = try Paths.GetEpisodesParameters(
            userID: authenticatedUser.id,
            fields: .MinimumFields,
            adjacentTo: item.id!,
            limit: 3
        )
        let request = Paths.getEpisodes(seriesID: seriesID, parameters: parameters)
        let response = try await send(request)

        // 4 possible states:
        //  1 - only current episode
        //  2 - two episodes with next episode
        //  3 - two episodes with previous episode
        //  4 - three episodes with current in middle

        // 1
        guard let items = response.value.items, items.count > 1 else { return }

        var previousItem: BaseItemDto?
        var nextItem: BaseItemDto?

        if items.count == 2 {
            if items[0].id == item.id {
                // 2
                nextItem = items[1]

            } else {
                // 3
                previousItem = items[0]
            }
        } else {
            nextItem = items[2]
            previousItem = items[0]
        }

        var nextProvider: MediaPlayerItemProvider?
        var previousProvider: MediaPlayerItemProvider?

        if let nextItem {
            nextProvider = MediaPlayerItemProvider(item: nextItem) { item in
                try await MediaPlayerItem.build(for: item) {
                    $0.userData?.playbackPositionTicks = .zero
                }
            }
        }

        if let previousItem {
            previousProvider = MediaPlayerItemProvider(item: previousItem) { item in
                try await MediaPlayerItem.build(for: item) {
                    $0.userData?.playbackPositionTicks = .zero
                }
            }
        }

        guard !Task.isCancelled else { return }

        await MainActor.run {
            self.nextItem = nextProvider
            self.previousItem = previousProvider
            self.hasNextItem = nextProvider != nil
            self.hasPreviousItem = previousProvider != nil
        }
    }
}

#if !os(tvOS)
extension EpisodeMediaPlayerQueue: MediaPlayerSupplementHeightProviding {

    func videoPlayerSupplementHeight(for size: CGSize, isCompact: Bool) -> CGFloat {
        let columns: CGFloat = UIDevice.isPhone ? 1.5 : 3.5
        let itemWidth = EpisodeCardLayout.itemWidth(for: size.width, columns: columns)
        let unconstrainedRailHeight = EpisodeCardLayout.height(for: itemWidth)
        let railHeight = isCompact ? unconstrainedRailHeight : min(unconstrainedRailHeight, 260)

        // SupplementContainerView contributes a focus boundary, top inset,
        // 36-point tab control, 12 points before the rail, and a 12-point
        // bottom inset below it.
        let tabBarHeight: CGFloat = 1 + EdgeInsets.edgePadding + 36 + 12 + 12
        return tabBarHeight + railHeight
    }
}
#endif

extension EpisodeMediaPlayerQueue {

    private struct EpisodeOverlay: PlatformView {

        @Environment(VideoPlayer.ViewState.self)
        private var viewState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        @ObservedObject
        var viewModel: SeriesItemViewModel

        @State
        private var selection: SeasonItemViewModel.ID?

        private func select(episode: BaseItemDto) {
            let provider = MediaPlayerItemProvider(item: episode) { item in
                try await MediaPlayerItem.build(for: item)
            }

            manager.playNewItem(provider: provider)
        }

        private func selectInitialSeason() {
            let seasonID = viewModel.selectorSeasonID(for: manager.item)
            let selectedSeason: SeasonItemViewModel? = if let selection,
                                                          let selectedSeasonID = selection
            {
                viewModel.seasons[id: selectedSeasonID]
            } else {
                nil
            }
            let season = seasonID.flatMap { viewModel.seasons[id: $0] }
                ?? selectedSeason
                ?? viewModel.seasons.first

            if let season {
                select(season: season)
            } else {
                selection = nil
            }
        }

        private func select(season: SeasonItemViewModel) {
            selection = season.id

            switch season.state {
            case .initial, .error:
                season.send(.refresh)
            case .content, .refreshing:
                break
            }
        }

        private func synchronizeSelection(with seasons: IdentifiedArrayOf<SeasonItemViewModel>) {
            guard seasons.isNotEmpty else {
                selection = nil
                return
            }

            // The seasons themselves are recreated whenever the series model
            // refreshes, so always resolve the current season again and load
            // its new view model rather than retaining a stale selection.
            selectInitialSeason()
        }

        private func loadAllSeasons(_ seasons: IdentifiedArrayOf<SeasonItemViewModel>) {
            for season in seasons {
                switch season.state {
                case .initial, .error:
                    season.send(.refresh)
                case .content, .refreshing:
                    break
                }
            }
        }

        #if os(iOS)
        var iOSView: some View {
            SeriesEpisodeSelector.EpisodeHStack(
                viewModel: viewModel,
                selection: $selection,
                episodeAction: select,
                focusItem: manager.item,
                maximumRailHeight: viewState.isCompact ? nil : 260,
                scrollsToSelection: false
            )
            .environmentObject(viewModel)
            .onAppear { selectInitialSeason() }
            .onChange(of: manager.item.id) { _, _ in
                selectInitialSeason()
            }
            .onReceive(viewModel.$seasons) { newSeasons in
                loadAllSeasons(newSeasons)
                synchronizeSelection(with: newSeasons)
            }
        }
        #else
        var iOSView: some View {
            EmptyView()
        }
        #endif

        var tvOSView: some View {
            RegularSeasonStackObserver(
                selection: $selection,
                action: select
            )
            .environmentObject(viewModel)
            .onFirstAppear {
                selectInitialSeason()
            }
            .onChange(of: manager.item.seasonID) { _, _ in
                selectInitialSeason()
            }
            .onReceive(viewModel.$seasons) { newSeasons in
                synchronizeSelection(with: newSeasons)
            }
        }
    }

    private struct RegularSeasonStackObserver: View {

        @EnvironmentObject
        private var seriesViewModel: SeriesItemViewModel

        let selection: Binding<SeasonItemViewModel.ID?>
        let action: (BaseItemDto) -> Void

        private var selectionViewModel: SeasonItemViewModel? {
            guard let id = selection.wrappedValue else { return nil }
            return seriesViewModel.seasons[id: id]
        }

        private struct _Body: View {

            #if !os(tvOS)
            @Environment(\.safeAreaInsets)
            private var safeAreaInsets: EdgeInsets
            #else
            @EnvironmentObject
            private var manager: MediaPlayerManager
            #endif

            @ObservedObject
            var selectionViewModel: SeasonItemViewModel

            let action: (BaseItemDto) -> Void

            @ViewBuilder
            private var contentView: some View {
                #if os(tvOS)
                ScrollViewReader { proxy in
                    SeriesEpisodeSelector.EpisodeRow(columnCount: 4.5) {
                        ForEach(
                            selectionViewModel.elements,
                            id: \.unwrappedIDHashOrZero
                        ) { episode in
                            EpisodeButton(episode: episode) {
                                action(episode)
                            }
                            .episodeHStackItemFrame()
                            .id(episode.unwrappedIDHashOrZero)
                        }
                    }
                    .onFirstAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo(manager.item.unwrappedIDHashOrZero, anchor: .leading)
                        }
                    }
                    .onChange(of: manager.item.id) { _, _ in
                        proxy.scrollTo(manager.item.unwrappedIDHashOrZero, anchor: .leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .ignoresSafeArea(.container, edges: .horizontal)
                .focusSection()
                #else
                CollectionHStack(
                    uniqueElements: selectionViewModel.elements,
                    id: \.unwrappedIDHashOrZero,
                    layout: .minimumWidth(columnWidth: 170, rows: 1)
                ) { item in
                    EpisodeButton(episode: item) {
                        action(item)
                    }
                }
                .clipsToBounds(false)
                .insets(horizontal: max(safeAreaInsets.leading, safeAreaInsets.trailing) + EdgeInsets.edgePadding)
                .itemSpacing(EdgeInsets.edgePadding / 2)
                .scrollBehavior(.continuousLeadingEdge)
                #endif
            }

            var body: some View {
                switch selectionViewModel.state {
                case .content:
                    if selectionViewModel.elements.isNotEmpty {
                        contentView
                    }
                case .initial, .refreshing:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .error:
                    SeasonErrorView(viewModel: selectionViewModel)
                }
            }
        }

        var body: some View {
            if let selectionViewModel {
                _Body(
                    selectionViewModel: selectionViewModel,
                    action: action
                )
            }
        }
    }

    private struct SeasonErrorView: View {

        @FocusState
        private var isRetryButtonFocused: Bool

        @ObservedObject
        var viewModel: SeasonItemViewModel

        // TODO: Supplements are dismissed on retry, probably due to focus change
        @ViewBuilder
        private var retryButton: some View {
            AlternateLayoutView {
                Label(L10n.retry, systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding()
                    .edgePadding(.horizontal)
                    .frame(height: UIDevice.isTV ? 80 : 40)
            } content: {
                Button {
                    viewModel.send(.refresh)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .foregroundStyle(.white)

                        Label(L10n.retry, systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.black)
                            .padding()
                            .edgePadding(.horizontal)
                    }
                }
                .buttonStyle(.card)
                .focused($isRetryButtonFocused)
                .frame(height: UIDevice.isTV ? 80 : 50)
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: EdgeInsets.edgePadding / 2) {
                Text(L10n.unknownError)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                retryButton
            }
            .edgePadding(.horizontal)
            .padding(.vertical, EdgeInsets.edgePadding / 2)
            .background {
                RoundedRectangle(cornerRadius: 32)
                    .fill(Material.thin)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32))
            .edgePadding()
            .focusSection()
        }
    }

    private struct EpisodePreview: View {

        @Default(.accentColor)
        private var accentColor

        @Environment(\.isSelected)
        private var isSelected

        let episode: BaseItemDto

        var body: some View {
            ZStack {
                Rectangle()
                    .fill(.complexSecondary)

                ImageView(episode.imageSource(.primary, maxWidth: 200))
                    .failure {
                        SystemImageContentView(systemName: episode.systemImage)
                    }
            }
            .overlay {
                if isSelected {
                    ContainerRelativeShape()
                        .stroke(
                            accentColor,
                            lineWidth: UIDevice.isTV ? 12 : 8
                        )
                        .clipped()
                }
            }
            .posterStyle(.landscape)
            .posterShadow()
            .hoverEffect(.highlight)
        }
    }

    private struct EpisodeDescription: View {

        let episode: BaseItemDto

        var body: some View {
            DotHStack {
                if let seasonEpisodeLabel = episode.seasonEpisodeLabel {
                    Text(seasonEpisodeLabel)
                }

                if let runtime = episode.runTimeLabel {
                    Text(runtime)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private struct EpisodeRow: View {

        @EnvironmentObject
        private var manager: MediaPlayerManager

        let episode: BaseItemDto
        let action: () -> Void

        private var isCurrentEpisode: Bool {
            manager.item.id == episode.id
        }

        var body: some View {
            ListRow(insets: .init(horizontal: EdgeInsets.edgePadding)) {
                EpisodePreview(episode: episode)
                    .frame(width: 110)
                    .padding(.vertical, 8)
            } content: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(episode.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    EpisodeDescription(episode: episode)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } action: {
                action()
            }
            .isSelected(isCurrentEpisode)
        }
    }

    private struct EpisodeButton: View {

        @Default(.accentColor)
        private var accentColor

        @EnvironmentObject
        private var manager: MediaPlayerManager

        let episode: BaseItemDto
        let action: () -> Void

        private var isCurrentEpisode: Bool {
            manager.item.id == episode.id
        }

        var body: some View {
            Group {
                #if os(tvOS)
                PlatformPosterButton(
                    item: episode,
                    type: .landscape,
                    overlayOptions: [.seasonEpisodeLabel, .durationLeft],
                    imageSources: [episode.imageSource(.primary, maxWidth: 300, quality: 90)],
                    usesContextMenu: false,
                    action: action
                ) {
                    PosterFallbackContentView(
                        title: episode.showTitle ? episode.displayTitle : nil,
                        systemName: episode.systemImage
                    )
                } overlay: {
                    ZStack {
                        PosterButtonDefaultOverlay(
                            item: episode,
                            overlayOptions: [.seasonEpisodeLabel, .durationLeft],
                            unplayedIndicatorType: .none,
                            alwaysShowsBottomContent: true
                        )

                        if isCurrentEpisode {
                            ContainerRelativeShape()
                                .stroke(accentColor, lineWidth: 12)
                                .clipped()
                        }
                    }
                }
                #else
                SupplementPosterButton(
                    item: episode._withLandscapeImages { [episode.imageSource(.primary, maxWidth: $0, quality: $1)] },
                    action: action
                ) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(episode.displayTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1, reservesSpace: true)

                        EpisodeDescription(episode: episode)
                            .font(UIDevice.isTV ? .caption : .subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1, reservesSpace: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                #endif
            }
            .isSelected(isCurrentEpisode)
        }
    }
}
