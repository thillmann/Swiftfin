//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI
import SwiftUI

struct HomeView: View {

    private enum HomeFocusSection: Hashable {
        case cinematicResume
        case cinematicRecentlyAdded
        case nextUp
        case recentlyAdded
        case upcomingMovies
        case upcomingTVShows
        case studios
        case networks
        case genres
        case library(ObjectIdentifier)
    }

    private let bottomPadding: CGFloat = 80
    private let sectionSpacing: CGFloat = 40

    @Router
    private var router

    @FocusState
    private var focusedSection: HomeFocusSection?

    @State
    private var heroPresentation: HeroScrollPresentation = .hero

    @State
    private var focusExitResetTask: Task<Void, Never>?

    @State
    private var suppressFocusExitReset = false

    @StateObject
    private var viewModel = HomeViewModel()

    @Default(.Customization.Home.showRecentlyAdded)
    private var showRecentlyAdded
    @Default(.Customization.Indicators.showFavorited)
    private var showFavorited
    @Default(.Customization.Indicators.showProgress)
    private var showProgress
    @Default(.Customization.Indicators.showUnplayed)
    private var showUnplayed
    @Default(.Customization.Indicators.showPlayed)
    private var showPlayed

    private var posterOverlayOptions: PosterButtonOverlayOptions {
        PosterButtonOverlayOptions(
            showPlayed: showPlayed,
            showFavorited: showFavorited,
            showProgress: showProgress,
            showUnplayed: showUnplayed
        )
    }

    private var movieLibraries: [LatestInLibraryViewModel] {
        viewModel.libraries.filter { library in
            guard let collectionType = collectionType(for: library) else { return false }
            return [.homevideos, .movies, .musicvideos].contains(collectionType)
        }
    }

    private var tvShowLibraries: [LatestInLibraryViewModel] {
        viewModel.libraries.filter { library in
            collectionType(for: library) == .tvshows
        }
    }

    private func collectionType(for library: LatestInLibraryViewModel) -> CollectionType? {
        (library.parent as? BaseItemDto)?.collectionType
    }

    @ViewBuilder
    private var contentView: some View {
        HeroScrollView(
            presentation: $heroPresentation,
            belowHeroAnchor: UnitPoint(x: 0.5, y: 0.4)
        ) {
            LazyVStack(alignment: .leading, spacing: sectionSpacing) {

                if viewModel.resumeItems.isNotEmpty {
                    CinematicResumeView(
                        viewModel: viewModel,
                        presentation: heroPresentation
                    )
                    .id(HeroScrollPresentation.hero)
                    .focused($focusedSection, equals: .cinematicResume)

                    NextUpView(viewModel: viewModel.nextUpViewModel)
                        .posterOverlayOptions(posterOverlayOptions, unplayedIndicatorType: showUnplayed)
                        .id(HeroScrollPresentation.belowHero)
                        .focused($focusedSection, equals: .nextUp)

                    if showRecentlyAdded {
                        RecentlyAddedView(viewModel: viewModel.recentlyAddedViewModel)
                            .posterOverlayOptions(posterOverlayOptions, unplayedIndicatorType: showUnplayed)
                            .focused($focusedSection, equals: .recentlyAdded)
                    }
                } else {
                    if showRecentlyAdded {
                        CinematicRecentlyAddedView(
                            viewModel: viewModel.recentlyAddedViewModel,
                            presentation: heroPresentation
                        )
                        .posterOverlayOptions(posterOverlayOptions, unplayedIndicatorType: showUnplayed)
                        .id(HeroScrollPresentation.hero)
                        .focused($focusedSection, equals: .cinematicRecentlyAdded)
                    }

                    NextUpView(viewModel: viewModel.nextUpViewModel)
                        .posterOverlayOptions(posterOverlayOptions, unplayedIndicatorType: showUnplayed)
                        .id(HeroScrollPresentation.belowHero)
                        .focused($focusedSection, equals: .nextUp)
                        .safeAreaPadding(.top, showRecentlyAdded ? 0 : 150)
                }

                ForEach(movieLibraries) { viewModel in
                    LatestInLibraryView(viewModel: viewModel)
                        .posterOverlayOptions(posterOverlayOptions, unplayedIndicatorType: showUnplayed)
                        .focused(
                            $focusedSection,
                            equals: .library(ObjectIdentifier(viewModel))
                        )
                }

                if SeerrIntegration.isAvailable {
                    UpcomingMediaView(
                        title: "\(L10n.upcoming) \(L10n.movies)",
                        mediaType: .movies,
                        items: viewModel.upcomingMovies,
                        onMarkRequested: viewModel.markUpcomingRequested,
                        onPrepareForNavigation: prepareForNavigation
                    )
                    .focused($focusedSection, equals: .upcomingMovies)

                    BrowseBySectionView(
                        group: .studios,
                        onPrepareForNavigation: prepareForNavigation
                    )
                    .focused($focusedSection, equals: .studios)
                }

                ForEach(tvShowLibraries) { viewModel in
                    LatestInLibraryView(viewModel: viewModel)
                        .posterOverlayOptions(posterOverlayOptions, unplayedIndicatorType: showUnplayed)
                        .focused(
                            $focusedSection,
                            equals: .library(ObjectIdentifier(viewModel))
                        )
                }

                if SeerrIntegration.isAvailable {
                    UpcomingMediaView(
                        title: "\(L10n.upcoming) \(L10n.tvShowsCapitalized)",
                        mediaType: .tv,
                        items: viewModel.upcomingTVShows,
                        onMarkRequested: viewModel.markUpcomingRequested,
                        onPrepareForNavigation: prepareForNavigation
                    )
                    .focused($focusedSection, equals: .upcomingTVShows)

                    BrowseBySectionView(
                        group: .networks,
                        onPrepareForNavigation: prepareForNavigation
                    )
                    .focused($focusedSection, equals: .networks)
                }

                GenresView(genres: viewModel.genres)
                    .onSelectGenre(prepareForNavigation)
                    .focused($focusedSection, equals: .genres)
            }
            .padding(.bottom, bottomPadding)
        }
    }

    var body: some View {
        ZStack {
            Color.clear

            switch viewModel.state {
            case .content:
                contentView
            case let .error(error):
                ErrorView(error: error)
            case .initial, .refreshing:
                ProgressView()
            }
        }
        .animation(.linear(duration: 0.1), value: viewModel.state)
        .onChange(of: focusedSection) { _, section in
            focusExitResetTask?.cancel()

            switch section {
            case .cinematicResume, .cinematicRecentlyAdded:
                suppressFocusExitReset = false
                updateHeroPresentation(.hero)
            case .nextUp, .recentlyAdded, .upcomingMovies, .upcomingTVShows, .studios, .networks, .genres, .library:
                suppressFocusExitReset = false
                updateHeroPresentation(.belowHero)
            case nil:
                guard !suppressFocusExitReset else { return }
                scheduleFocusExitReset()
            }
        }
        .refreshable {
            viewModel.send(.refresh)
        }
        .onAppear {
            viewModel.send(.refresh)
        }
        .onDisappear {
            focusExitResetTask?.cancel()
            suppressFocusExitReset = false
        }
        .ignoresSafeArea()
    }

    private func updateHeroPresentation(_ presentation: HeroScrollPresentation) {
        withAnimation(.easeOut(duration: 0.6)) {
            heroPresentation = presentation
        }
    }

    private func scheduleFocusExitReset() {
        focusExitResetTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }

            guard !Task.isCancelled, focusedSection == nil else { return }

            updateHeroPresentation(.hero)
        }
    }

    private func prepareForNavigation() {
        focusExitResetTask?.cancel()
        suppressFocusExitReset = true
    }
}
