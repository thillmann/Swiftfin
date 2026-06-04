//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import Foundation
import JellyfinAPI
import SwiftUI

extension SeriesEpisodeSelector {

    struct EpisodeHStack: View {

        @Environment(\.cinematicFocusRegionChanged)
        private var focusRegionChanged

        @FocusState
        private var focusedEpisodeID: String?

        @ObservedObject
        var viewModel: SeasonItemViewModel

        @Binding
        var activeEpisodeID: String?
        @Binding
        var focusedRegion: SeriesEpisodeSelector.FocusRegion?

        @State
        private var didScrollToPlayButtonItem = false

        @StateObject
        private var proxy = CollectionHStackProxy()

        let playButtonItem: BaseItemDto?

        private var preferredEpisodeFocusID: String? {
            switch viewModel.state {
            case .content:
                if viewModel.elements.isEmpty {
                    return "emptyCard"
                }

                if let activeEpisodeID,
                   viewModel.elements.contains(where: { $0.id == activeEpisodeID })
                {
                    return activeEpisodeID
                }

                if let playButtonItem,
                   viewModel.elements.contains(where: { $0.id == playButtonItem.id })
                {
                    return playButtonItem.id
                }

                return viewModel.elements.first?.id
            case .error:
                return "errorCard"
            case .initial, .refreshing:
                return "loadingCard"
            }
        }

        private func scrollToPreferredEpisode(animated: Bool = false) {
            guard let preferredEpisodeFocusID,
                  let episode = viewModel.elements.first(where: { $0.id == preferredEpisodeFocusID })
            else { return }

            proxy.scrollTo(id: episode.unwrappedIDHashOrZero, animated: animated)
        }

        private func updateActiveEpisodeForCurrentSeason() {
            guard viewModel.state == .content,
                  activeEpisodeID == nil || !viewModel.elements.contains(where: { $0.id == activeEpisodeID })
            else { return }

            activeEpisodeID = preferredEpisodeFocusID
        }

        // MARK: - Content View

        private func contentView(viewModel: SeasonItemViewModel) -> some View {
            CollectionHStack(
                uniqueElements: viewModel.elements,
                id: \.unwrappedIDHashOrZero,
                columns: 3.5
            ) { episode in
                SeriesEpisodeSelector.EpisodeCard(
                    episode: episode,
                    isEntryFocused: focusedEpisodeID == episode.id
                ) { isFocused in
                    if isFocused {
                        focusedEpisodeID = episode.id
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollBehavior(.continuousLeadingEdge)
            .insets(horizontal: EdgeInsets.edgePadding)
            .itemSpacing(EdgeInsets.edgePadding / 2)
            .proxy(proxy)
            .onFirstAppear {
                guard !didScrollToPlayButtonItem else { return }
                didScrollToPlayButtonItem = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    updateActiveEpisodeForCurrentSeason()
                    scrollToPreferredEpisode()
                }
            }
        }

        // MARK: - Body

        var body: some View {
            ZStack {
                PlaceholderHStack()

                Group {
                    switch viewModel.state {
                    case .content:
                        if viewModel.elements.isEmpty {
                            EmptyHStack(focusedEpisodeID: $focusedEpisodeID)
                        } else {
                            contentView(viewModel: viewModel)
                        }
                    case let .error(error):
                        ErrorHStack(viewModel: viewModel, error: error, focusedEpisodeID: $focusedEpisodeID)
                    case .initial, .refreshing:
                        LoadingHStack(focusedEpisodeID: $focusedEpisodeID)
                    }
                }.transition(.opacity.animation(.linear(duration: 0.1)))
            }
            .padding(.bottom, 45)
            .focusSection()
            .onChange(of: viewModel.id) {
                updateActiveEpisodeForCurrentSeason()

                DispatchQueue.main.async {
                    scrollToPreferredEpisode()
                }
            }
            .onChange(of: activeEpisodeID) { _, _ in
                DispatchQueue.main.async {
                    scrollToPreferredEpisode()
                }
            }
            .onChange(of: focusedEpisodeID) { _, newValue in
                guard let newValue else { return }

                activeEpisodeID = newValue
                focusedRegion = .episodes
                focusRegionChanged(.episodes)
            }
            .onChange(of: viewModel.state) { _, newValue in
                if newValue == .content {
                    updateActiveEpisodeForCurrentSeason()
                }
            }
        }
    }

    // MARK: - Empty HStack

    struct EmptyHStack: View {

        let focusedEpisodeID: FocusState<String?>.Binding

        var body: some View {
            CollectionHStack(
                count: 1,
                columns: 3.5
            ) { _ in
                SeriesEpisodeSelector.EmptyCard()
                    .focused(focusedEpisodeID, equals: "emptyCard")
                    .padding(.horizontal, 4)
            }
            .insets(horizontal: EdgeInsets.edgePadding)
            .itemSpacing(EdgeInsets.edgePadding / 2)
            .scrollDisabled(true)
        }
    }

    // MARK: - Error HStack

    struct ErrorHStack: View {

        @ObservedObject
        var viewModel: SeasonItemViewModel

        let error: ErrorMessage
        let focusedEpisodeID: FocusState<String?>.Binding

        var body: some View {
            CollectionHStack(
                count: 1,
                columns: 3.5
            ) { _ in
                SeriesEpisodeSelector.ErrorCard(error: error) {
                    viewModel.send(.refresh)
                }
                .focused(focusedEpisodeID, equals: "errorCard")
                .padding(.horizontal, 4)
            }
            .insets(horizontal: EdgeInsets.edgePadding)
            .itemSpacing(EdgeInsets.edgePadding / 2)
            .scrollDisabled(true)
        }
    }

    // MARK: - Loading HStack

    struct LoadingHStack: View {

        let focusedEpisodeID: FocusState<String?>.Binding

        var body: some View {
            CollectionHStack(
                count: 1,
                columns: 3.5
            ) { _ in
                SeriesEpisodeSelector.LoadingCard()
                    .focused(focusedEpisodeID, equals: "loadingCard")
                    .padding(.horizontal, 4)
            }
            .insets(horizontal: EdgeInsets.edgePadding)
            .itemSpacing(EdgeInsets.edgePadding / 2)
            .scrollDisabled(true)
        }
    }

    // MARK: - Placeholder HStack

    struct PlaceholderHStack: View {

        var body: some View {
            CollectionHStack(
                count: 1,
                columns: 3.5
            ) { _ in
                SeriesEpisodeSelector.EmptyCard()
                    .padding(.horizontal, 4)
            }
            .insets(horizontal: EdgeInsets.edgePadding)
            .itemSpacing(EdgeInsets.edgePadding / 2)
            .opacity(0)
            .allowsHitTesting(false)
            .scrollDisabled(true)
        }
    }
}
