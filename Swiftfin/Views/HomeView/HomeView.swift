//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import SwiftUI

// TODO: seems to redraw view when popped to sometimes?
//       - similar to MediaView TODO bug?
//       - indicated by snapping to the top
struct HomeView: View {

    @Default(.Customization.nextUpPosterType)
    private var nextUpPosterType
    @Default(.Customization.Home.showRecentlyAdded)
    private var showRecentlyAdded
    @Default(.Customization.recentlyAddedPosterType)
    private var recentlyAddedPosterType

    @Router
    private var router

    @StateObject
    private var viewModel = HomeViewModel()
    // These references must outlive HomeView redraws, but HomeView itself
    // must not subscribe to the backdrop's frame-rate scroll updates.
    @State
    private var heroCarouselState = HeroCarouselState()
    @State
    private var heroBackdropScrollState = HeroBackdropScrollState()

    private var isLoadingInitialResume: Bool {
        viewModel.state == .refreshing && viewModel.resumeItems.isEmpty
    }

    @ViewBuilder
    private func contentView(heroHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.resumeItems.isNotEmpty {
                    CinematicResumeItemView(
                        viewModel: viewModel,
                        carouselState: heroCarouselState,
                        height: heroHeight
                    )
                    .overlay(alignment: .top) {
                        heroHeader
                    }

                    lowerContent
                } else if isLoadingInitialResume {
                    resumeHeroLoadingPlaceholder(height: heroHeight)

                    lowerContent
                } else {
                    VStack(alignment: .leading, spacing: 32) {
                        contentHeader
                        homeSections
                    }
                    .background(Color.systemBackground)
                }
            }
            .padding(.bottom, 20)
        }
        .modifier(HomeScrollEdgeEffectModifier())
        .onScrollGeometryChange(for: CGFloat.self, of: { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        }, action: { _, offset in
            heroBackdropScrollState.offset = offset
        })
        .refreshable {
            viewModel.send(.refresh)
        }
    }

    private var homeSections: some View {
        VStack(alignment: .leading, spacing: 32) {
            NextUpView(viewModel: viewModel.nextUpViewModel)

            if showRecentlyAdded {
                RecentlyAddedView(viewModel: viewModel.recentlyAddedViewModel)
            }

            ForEach(viewModel.libraries) { viewModel in
                LatestInLibraryView(viewModel: viewModel)
            }
        }
    }

    private var lowerContent: some View {
        homeSections
            .padding(.top, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.systemBackground)
    }

    private func resumeHeroLoadingPlaceholder(height: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [.black, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )

            ProgressView()
                .controlSize(.regular)
                .tint(.white)
        }
        .frame(height: height)
        .overlay(alignment: .top) {
            heroHeader
        }
    }

    @ViewBuilder
    private var heroHeader: some View {
        if !UIDevice.isPad {
            HStack(alignment: .center) {
                Text(L10n.home)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)

                Spacer()

                headerTrailingContent
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
        }
    }

    @ViewBuilder
    private var contentHeader: some View {
        if !UIDevice.isPad {
            HStack(alignment: .center) {
                Text(L10n.home)
                    .font(.largeTitle.weight(.bold))

                Spacer()

                headerTrailingContent
            }
            .edgePadding(.horizontal)
            .padding(.top, 60)
        }
    }

    @ViewBuilder
    private var headerTrailingContent: some View {
        if !UIDevice.isPad, viewModel.backgroundStates.contains(.refresh) {
            ProgressView()
        }

        if !UIDevice.isPad, let userSession = viewModel.userSession {
            SettingsBarButton(
                server: userSession.server,
                user: userSession.user
            ) {
                router.route(to: .settings)
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let heroHeightRatio: CGFloat = UIDevice.isPad && proxy.size.isPortrait ? 0.4 : 0.8
            let detailBackdropSize = CGSize(
                width: proxy.size.width,
                height: (proxy.size.height + proxy.safeAreaInsets.vertical) * heroHeightRatio
            )

            ZStack(alignment: .top) {
                Color.systemBackground

                if viewModel.resumeItems.isNotEmpty {
                    CinematicResumeBackdrop(
                        items: viewModel.resumeItems.elements,
                        carouselState: heroCarouselState,
                        scrollState: heroBackdropScrollState,
                        viewportSize: detailBackdropSize
                    )
                }

                switch viewModel.state {
                case .content, .refreshing:
                    contentView(heroHeight: detailBackdropSize.height)
                case let .error(error):
                    ErrorView(error: error, allowsServerSelection: true)
                case .initial:
                    ProgressView()
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .onFirstAppear {
            viewModel.send(.refresh)
        }
        .topBarTrailing {
            if UIDevice.isPad, let userSession = viewModel.userSession {
                SettingsBarButton(
                    server: userSession.server,
                    user: userSession.user,
                    appearance: .toolbarIcon
                ) {
                    router.route(to: .settings)
                }
            }
        }
        .if(UIDevice.isPhone) { view in
            view.toolbar(.hidden, for: .navigationBar)
        }
        .refreshable {
            viewModel.send(.refresh)
        }
        .sinceLastDisappear { interval in
            if interval > 60 || viewModel.notificationsReceived.contains(.itemMetadataDidChange) {
                viewModel.send(.backgroundRefresh)
                viewModel.notificationsReceived.remove(.itemMetadataDidChange)
            }
        }
    }
}

private struct HomeScrollEdgeEffectModifier: ViewModifier {

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if UIDevice.isPad {
                content.scrollEdgeEffectHidden(true, for: [.top, .bottom])
            } else {
                content.scrollEdgeEffectHidden(true, for: .bottom)
            }
        } else {
            content
        }
    }
}
