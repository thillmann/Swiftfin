//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension SeriesEpisodeSelector {

    struct SeasonsHStack: View {

        // MARK: - Environment & Observed Objects

        @Environment(\.cinematicFocusRegionChanged)
        private var focusRegionChanged

        @ObservedObject
        var viewModel: SeriesItemViewModel

        // MARK: - Active Season Binding

        @Binding
        var activeSeasonID: SeasonItemViewModel.ID?
        @Binding
        var focusedRegion: SeriesEpisodeSelector.FocusRegion?

        // MARK: - Focus Variables

        @FocusState
        private var focusedSeason: SeasonItemViewModel.ID?
        @Namespace
        private var focusScope

        @State
        private var didScrollToPlayButtonSeason = false

        // MARK: - Body

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
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
                .mask {
                    VStack(spacing: 0) {
                        Color.white

                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 20)
                    }
                }
                .onChange(of: focusedSeason) { oldValue, newValue in
                    guard let newValue else { return }

                    if oldValue == nil || focusedRegion != .seasons,
                       let activeSeasonID,
                       newValue != activeSeasonID
                    {
                        DispatchQueue.main.async {
                            proxy.scrollTo(activeSeasonID)
                            focusedSeason = activeSeasonID
                        }
                        return
                    }

                    activeSeasonID = newValue
                    focusedRegion = .seasons
                    focusRegionChanged(.belowHeader)
                }
                .onChange(of: activeSeasonID) { _, newValue in
                    guard let newValue else { return }

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
        }

        // MARK: - Season Button

        @ViewBuilder
        private func seasonButton(season: SeasonItemViewModel) -> some View {
            let isFocused = focusedSeason == season.id
            let isSelected = activeSeasonID == season.id

            Button {
                activeSeasonID = season.id
            } label: {
                Marquee(season.season.displayTitle, animateWhenFocused: true)
                    .frame(maxWidth: 300)
                    .fontWeight(.semibold)
                    .foregroundStyle(isFocused ? .black : .white.opacity(isSelected ? 1 : 0.72))
                    .padding(.horizontal, 32)
                    .frame(height: FeatureButtonTokens.baseHeight)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.white.opacity(isFocused ? 1 : isSelected ? 0.3 : 0))
                    }
            }
            .focused($focusedSeason, equals: season.id)
            .buttonStyle(.borderless)
            .focusEffectDisabled()
            .scaleEffect(isFocused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .padding(.vertical)
        }
    }
}
