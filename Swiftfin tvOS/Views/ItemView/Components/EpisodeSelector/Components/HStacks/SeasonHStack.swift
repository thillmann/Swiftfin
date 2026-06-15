//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension SeriesEpisodeSelector {

    struct LoadingSeasonsHStack: View {

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    Button("Season 1") {}
                        .buttonStyle(
                            SeasonButtonStyle(
                                isFocused: false,
                                isSelected: true
                            )
                        )
                        .disabled(true)
                        .focusable(false)
                        .padding(.vertical)
                }
                .padding(.horizontal, EdgeInsets.edgePadding)
            }
            .padding(.bottom, 24)
            .scrollClipDisabled()
        }
    }

    struct SeasonsHStack: View {

        // MARK: - Environment & Observed Objects

        @Environment(\.cinematicFocusRegionChanged)
        private var focusRegionChanged
        @Environment(\.cinematicScrollTargetRequested)
        private var scrollTargetRequested

        @ObservedObject
        var viewModel: SeriesItemViewModel

        // MARK: - Active Season Binding

        @Binding
        var activeSeasonID: SeasonItemViewModel.ID
        @Binding
        var focusedRegion: SeriesEpisodeSelector.FocusRegion?
        let onSeasonFocused: (SeasonItemViewModel.ID, SeasonScrollReason) -> Void
        let onSeasonSelected: (SeasonItemViewModel.ID, SeasonScrollReason) -> Void

        // MARK: - Focus Variables

        @FocusState
        private var focusedSeason: SeasonItemViewModel.ID?
        @Namespace
        private var focusScope

        @State
        private var didScrollToPlayButtonSeason = false
        @State
        private var seasonSelectionTask: Task<Void, Never>?
        @State
        private var pendingSeasonSelectionID: SeasonItemViewModel.ID?

        // MARK: - Body

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(viewModel.seasons) { season in
                            seasonButton(season: season)
                                .id(season.id)
                        }
                    }
                    .padding(.horizontal, EdgeInsets.edgePadding)
                }
                .padding(.bottom, 24)
                .focusSection()
                .focusScope(focusScope)
                .defaultFocus(
                    $focusedSeason,
                    activeSeasonID,
                    priority: .userInitiated
                )
                .onChange(of: focusedSeason) { oldValue, newValue in
                    guard let newValue else { return }

                    let oldSeasonID = oldValue.flatMap(\.self)

                    let enteredSeasonRow = oldValue == nil || focusedRegion != .seasons

                    if enteredSeasonRow {
                        focusedRegion = .seasons
                        focusRegionChanged(.belowHeader)
                        scrollTargetRequested(.episodeSelector)
                    }

                    debounceActiveSeasonSelection(
                        newValue,
                        reason: focusReason(from: oldSeasonID, to: newValue)
                    )
                }
                .onChange(of: activeSeasonID) { _, newValue in
                    guard let newValue else { return }

                    if pendingSeasonSelectionID != nil {
                        seasonSelectionTask?.cancel()
                        pendingSeasonSelectionID = nil
                    }

                    DispatchQueue.main.async {
                        proxy.scrollTo(newValue)
                    }
                }
                .onFirstAppear {
                    guard !didScrollToPlayButtonSeason else { return }
                    didScrollToPlayButtonSeason = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        guard let activeSeasonID else { return }

                        proxy.scrollTo(activeSeasonID)
                    }
                }
            }
            .scrollClipDisabled()
            .onDisappear {
                seasonSelectionTask?.cancel()
            }
        }

        // MARK: - Season Button

        private func seasonButton(season: SeasonItemViewModel) -> some View {
            let isFocused = focusedRegion == .seasons && focusedSeason == season.id
            let isSelected = activeSeasonID == season.id

            return Button(season.season.displayTitle) {
                selectSeason(season.id)
            }
            .focused($focusedSeason, equals: season.id)
            .buttonStyle(
                SeasonButtonStyle(
                    isFocused: isFocused,
                    isSelected: isSelected
                )
            )
            .focusEffectDisabled()
            .padding(.vertical)
        }

        private func selectSeason(_ seasonID: SeasonItemViewModel.ID) {
            seasonSelectionTask?.cancel()
            pendingSeasonSelectionID = nil
            onSeasonSelected(seasonID, .selected)
        }

        // MARK: - Active Season Selection

        private func debounceActiveSeasonSelection(
            _ seasonID: SeasonItemViewModel.ID,
            reason: SeasonScrollReason
        ) {
            guard seasonID != activeSeasonID else { return }

            seasonSelectionTask?.cancel()
            pendingSeasonSelectionID = seasonID
            seasonSelectionTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 300_000_000)
                } catch {
                    return
                }

                await MainActor.run {
                    guard pendingSeasonSelectionID == seasonID else { return }

                    pendingSeasonSelectionID = nil
                    onSeasonFocused(seasonID, reason)
                }
            }
        }

        private func focusReason(
            from oldSeasonID: SeasonItemViewModel.ID,
            to newSeasonID: SeasonItemViewModel.ID
        ) -> SeasonScrollReason {
            guard let newIndex = viewModel.seasons.firstIndex(where: { $0.id == newSeasonID }) else {
                return .focusedFromPreviousSeason
            }

            guard let oldSeasonID,
                  let oldIndex = viewModel.seasons.firstIndex(where: { $0.id == oldSeasonID }),
                  newIndex < oldIndex
            else {
                return .focusedFromPreviousSeason
            }

            return .focusedFromNextSeason
        }
    }
}

private struct SeasonButtonStyle: ButtonStyle {

    let isFocused: Bool
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(isFocused ? .black : .white.opacity(isSelected ? 1 : 0.72))
            .padding(.horizontal, 32)
            .frame(height: FeatureButtonTokens.baseHeight)
            .background {
                Capsule(style: .continuous)
                    .fill(.white.opacity(isFocused ? 1 : isSelected ? 0.3 : 0))
            }
            .scaleEffect(isFocused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
