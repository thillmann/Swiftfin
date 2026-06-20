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
        case nextUp
        case recentlyAdded
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

    @StateObject
    private var viewModel = HomeViewModel()

    @Default(.Customization.Home.showRecentlyAdded)
    private var showRecentlyAdded

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
                        .id(HeroScrollPresentation.belowHero)
                        .focused($focusedSection, equals: .nextUp)

                    if showRecentlyAdded {
                        RecentlyAddedView(viewModel: viewModel.recentlyAddedViewModel)
                            .focused($focusedSection, equals: .recentlyAdded)
                    }
                } else {
                    if showRecentlyAdded {
                        CinematicRecentlyAddedView(viewModel: viewModel.recentlyAddedViewModel)
                    }

                    NextUpView(viewModel: viewModel.nextUpViewModel)
                        .safeAreaPadding(.top, 150)
                }

                ForEach(viewModel.libraries) { viewModel in
                    LatestInLibraryView(viewModel: viewModel)
                        .focused(
                            $focusedSection,
                            equals: .library(ObjectIdentifier(viewModel))
                        )
                }
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
            guard viewModel.resumeItems.isNotEmpty else { return }

            switch section {
            case .cinematicResume:
                withAnimation(.easeOut(duration: 0.6)) {
                    heroPresentation = .hero
                }
            case .nextUp, .recentlyAdded, .library:
                withAnimation(.easeOut(duration: 0.6)) {
                    heroPresentation = .belowHero
                }
            case nil:
                break
            }
        }
        .refreshable {
            viewModel.send(.refresh)
        }
        .onAppear {
            viewModel.send(.refresh)
        }
        .ignoresSafeArea()
    }
}
