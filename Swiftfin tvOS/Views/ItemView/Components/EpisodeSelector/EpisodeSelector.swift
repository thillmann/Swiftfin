//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftUI

struct SeriesEpisodeSelector: View {

    enum FocusRegion {
        case seasons
        case episodes
    }

    // MARK: - Observed & Environment Objects

    @ObservedObject
    var viewModel: SeriesItemViewModel

    // MARK: - State Variables

    @State
    private var didSelectPlayButtonSeason = false
    @State
    private var activeSeasonID: SeasonItemViewModel.ID = nil
    @State
    private var focusedRegion: FocusRegion?
    @State
    private var seasonScrollRequest: SeasonScrollRequest?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.seasons.isEmpty {
                LoadingSeasonsHStack()
                LoadingEpisodeHStack()
            } else {
                SeasonsHStack(
                    viewModel: viewModel,
                    activeSeasonID: $activeSeasonID,
                    focusedRegion: $focusedRegion,
                    onSeasonFocused: requestSeasonScroll,
                    onSeasonSelected: requestSeasonScroll
                )

                EpisodeHStack(
                    viewModel: viewModel,
                    activeSeasonID: $activeSeasonID,
                    focusedRegion: $focusedRegion,
                    seasonScrollRequest: $seasonScrollRequest
                )
            }
        }
        .id(ItemView.CinematicScrollTarget.episodeSelector)
        .onReceive(viewModel.playButtonItem.publisher) { newValue in
            selectInitialSeason(from: newValue)
        }
        .onChange(of: viewModel.seasons.map(\.id)) { _, _ in
            selectInitialSeason(from: viewModel.playButtonItem)
        }
    }

    private func requestSeasonScroll(
        seasonID: SeasonItemViewModel.ID,
        reason: SeasonScrollReason
    ) {
        activeSeasonID = seasonID
        seasonScrollRequest = SeasonScrollRequest(
            seasonID: seasonID,
            reason: reason
        )
    }

    private func selectInitialSeason(from playButtonItem: BaseItemDto?) {
        guard !didSelectPlayButtonSeason,
              let playButtonItem,
              viewModel.seasons.isNotEmpty
        else { return }

        didSelectPlayButtonSeason = true

        if let playButtonSeason = viewModel.seasons.first(where: { $0.id == playButtonItem.seasonID }) {
            requestSeasonScroll(
                seasonID: playButtonSeason.id,
                reason: .initialPlayButtonItem(episodeID: playButtonItem.id)
            )
        } else {
            requestSeasonScroll(
                seasonID: viewModel.seasons.first?.id,
                reason: .selected
            )
        }
    }
}

extension SeriesEpisodeSelector {

    struct EpisodeSelectorSnapshot {

        var rows: [EpisodeSelectorRowEntry] = []
        var episodeToSeason: [LoadedEpisode.ID: SeasonItemViewModel.ID] = [:]
        var seasonTargets: [SeasonItemViewModel.ID: SeasonTargets] = [:]
        var errorSeasonIDs: Set<SeasonItemViewModel.ID> = []
    }

    enum EpisodeSelectorRowEntry: Identifiable {

        case episode(LoadedEpisode)
        case seasonError(LoadedSeasonError)

        var id: String {
            switch self {
            case let .episode(episode):
                "episode-\(episode.id)"
            case let .seasonError(error):
                "season-error-\(error.id)"
            }
        }
    }

    struct LoadedEpisode: Identifiable {

        let id: String
        let seasonID: SeasonItemViewModel.ID
        let episode: BaseItemDto
        let title: String
        let locator: String
        let overview: String
        let releaseDateLabel: String?

        init?(
            episode: BaseItemDto,
            seasonID: SeasonItemViewModel.ID
        ) {
            guard let id = episode.id else { return nil }

            self.id = id
            self.seasonID = seasonID
            self.episode = episode
            self.title = episode.displayTitle
            self.locator = episode.episodeLocator ?? .emptyDash

            if episode.isUnaired {
                self.overview = episode.airDateLabel ?? L10n.noOverviewAvailable
            } else {
                self.overview = episode.overview ?? L10n.noOverviewAvailable
            }

            self.releaseDateLabel = episode.premiereDate.map {
                SeriesEpisodeSelector.episodeReleaseDateFormatter.string(from: $0)
            }
        }
    }

    struct LoadedSeasonError: Identifiable {

        let id: String
        let seasonID: SeasonItemViewModel.ID
        let viewModel: SeasonItemViewModel
        let error: ErrorMessage
    }

    struct SeasonTargets {

        let firstEpisodeID: LoadedEpisode.ID
        let lastEpisodeID: LoadedEpisode.ID
    }

    struct SeasonScrollRequest: Identifiable {

        let id = UUID()
        let seasonID: SeasonItemViewModel.ID
        let reason: SeasonScrollReason
    }

    enum SeasonScrollReason {

        case focusedFromPreviousSeason
        case focusedFromNextSeason
        case initialPlayButtonItem(episodeID: LoadedEpisode.ID?)
        case selected

        var anchor: UnitPoint {
            switch self {
            case .focusedFromNextSeason:
                .trailing
            case .focusedFromPreviousSeason, .initialPlayButtonItem, .selected:
                .leading
            }
        }
    }

    private static let episodeReleaseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()
}
