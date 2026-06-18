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
    }

    private enum HomeScrollTarget: Hashable {
        case nextUp
    }

    private let bottomPadding: CGFloat = 80
    private let sectionSpacing: CGFloat = 40

    @Router
    private var router

    @FocusState
    private var focusedSection: HomeFocusSection?

    @State
    private var revealsNextSection = true

    @StateObject
    private var viewModel = HomeViewModel()

    @Default(.Customization.Home.showRecentlyAdded)
    private var showRecentlyAdded

    @ViewBuilder
    private var contentView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: sectionSpacing) {

                    if viewModel.resumeItems.isNotEmpty {
                        CinematicResumeView(
                            viewModel: viewModel,
                            revealsNextSection: revealsNextSection
                        )
                        .focused($focusedSection, equals: .cinematicResume)

                        NextUpView(
                            viewModel: viewModel.nextUpViewModel,
                            onFirstPosterFocused: {
                                scrollToNextUp(with: scrollProxy)
                            }
                        )
                        .id(HomeScrollTarget.nextUp)
                        .focused($focusedSection, equals: .nextUp)

                        if showRecentlyAdded {
                            RecentlyAddedView(viewModel: viewModel.recentlyAddedViewModel)
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
                    }
                }
                .padding(.bottom, bottomPadding)
            }
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
            switch section {
            case .cinematicResume:
                revealsNextSection = true
            case .nextUp:
                revealsNextSection = false
            case nil:
                break
            }
        }
        .refreshable {
            viewModel.send(.refresh)
        }
        .onFirstAppear {
            viewModel.send(.refresh)
        }
        .ignoresSafeArea()
        .sinceLastDisappear { _ in
            viewModel.send(.backgroundRefresh)
            viewModel.notificationsReceived.remove(.itemMetadataDidChange)
        }
    }

    private func scrollToNextUp(with proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.35)) {
            proxy.scrollTo(HomeScrollTarget.nextUp, anchor: .top)
        }
    }
}
