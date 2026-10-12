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

struct SeriesEpisodeSelector: View {

    @ObservedObject
    var viewModel: SeriesItemViewModel

    @State
    private var didSelectPlayButtonSeason = false
    @State
    private var selection: SeasonItemViewModel.ID?
    @State
    private var isEpisodeRailInteractionBlocked = false

    private var selectionViewModel: SeasonItemViewModel? {
        viewModel.seasons.first(where: { $0.id == selection })
    }

    private var isShowingPlaceholder: Bool {
        selectionViewModel == nil
    }

    private var seasonSelectorMenu: some View {
        Menu {
            ForEach(viewModel.seasons, id: \.season.id) { seasonViewModel in
                Button {
                    protectEpisodeRailFromDismissalTap()

                    // Let the menu finish dismissing before changing the rail. Updating the
                    // selection can require SwiftUI to resolve a distant lazy-stack target.
                    DispatchQueue.main.async {
                        selection = seasonViewModel.id
                    }
                } label: {
                    if seasonViewModel.id == selection {
                        Label(seasonViewModel.season.displayTitle, systemImage: "checkmark")
                    } else {
                        Text(seasonViewModel.season.displayTitle)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectionViewModel?.season.displayTitle ?? .emptyDash)
                    .font(.title2)
                    .fontWeight(.semibold)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibility(addTraits: [.isHeader])
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.season)
        .accessibilityValue(selectionViewModel?.season.displayTitle ?? .emptyDash)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isShowingPlaceholder {
                LoadingSelector()
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    seasonSelectorMenu
                        .edgePadding(.horizontal)

                    EpisodeHStack(viewModel: viewModel, selection: $selection)
                        .allowsHitTesting(!isEpisodeRailInteractionBlocked)
                        .overlay {
                            if isEpisodeRailInteractionBlocked {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture {}
                                    .accessibilityHidden(true)
                            }
                        }
                }
                .transition(.opacity)
            }
        }
        .animation(PosterLoadingPlaceholder.transitionAnimation, value: isShowingPlaceholder)
        .onReceive(viewModel.$seasons) { seasons in
            for seasonViewModel in seasons where seasonViewModel.state == .initial {
                seasonViewModel.send(.refresh)
            }
        }
        .onReceive(viewModel.$playButtonItem.compactMap(\.self)) { newValue in
            Task { @MainActor in
                selectInitialSeason(for: newValue)
            }
        }
        .onReceive(viewModel.$isLoadingPlayButtonItem.removeDuplicates()) { isLoading in
            Task { @MainActor in
                guard !isLoading, selectionViewModel == nil else { return }

                selection = viewModel.seasons.first?.id
            }
        }
    }

    private func protectEpisodeRailFromDismissalTap() {
        isEpisodeRailInteractionBlocked = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            isEpisodeRailInteractionBlocked = false
        }
    }

    @MainActor
    private func selectInitialSeason(for playButtonItem: BaseItemDto) {
        guard !didSelectPlayButtonSeason, viewModel.seasons.isNotEmpty else { return }

        didSelectPlayButtonSeason = true

        if let playButtonSeasonID = viewModel.selectorSeasonID(for: playButtonItem) {
            selection = playButtonSeasonID
        } else {
            selection = viewModel.seasons.first?.id
        }
    }
}

extension SeriesEpisodeSelector {

    struct LoadingSelector: View {

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(L10n.seasonNumber(0))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .redacted(reason: .placeholder)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.title3.weight(.semibold))
                        .hidden()
                }
                .edgePadding(.horizontal)

                LoadingHStack()
            }
            .accessibilityHidden(true)
        }
    }
}
