//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
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
    private var activeSeasonID: SeasonItemViewModel.ID?
    @State
    private var activeEpisodeID: String?
    @State
    private var focusedRegion: FocusRegion?

    // MARK: - Calculated Variables

    private var activeSeasonViewModel: SeasonItemViewModel? {
        viewModel.seasons.first(where: { $0.id == activeSeasonID })
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            SeasonsHStack(
                viewModel: viewModel,
                activeSeasonID: $activeSeasonID,
                focusedRegion: $focusedRegion
            )

            if let activeSeasonViewModel {
                EpisodeHStack(
                    viewModel: activeSeasonViewModel,
                    activeEpisodeID: $activeEpisodeID,
                    focusedRegion: $focusedRegion,
                    playButtonItem: viewModel.playButtonItem
                )
            }
        }
        .onReceive(viewModel.playButtonItem.publisher) { newValue in

            guard !didSelectPlayButtonSeason else { return }
            didSelectPlayButtonSeason = true

            if let playButtonSeason = viewModel.seasons.first(where: { $0.id == newValue.seasonID }) {
                activeSeasonID = playButtonSeason.id
            } else {
                activeSeasonID = viewModel.seasons.first?.id
            }

            activeEpisodeID = newValue.id
        }
        .onChange(of: activeSeasonID) { _, _ in
            guard let activeSeasonViewModel else { return }

            if activeSeasonViewModel.state == .initial {
                activeSeasonViewModel.send(.refresh)
            }
        }
    }
}
