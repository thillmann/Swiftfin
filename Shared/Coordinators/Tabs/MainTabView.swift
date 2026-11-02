//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect

// TODO: move popup to router
//       - or, make tab view environment object

// TODO: fix weird tvOS icon rendering
struct MainTabView: View {

    #if os(iOS)
    @MainActor
    final class SearchQueryState: ObservableObject {

        @Published
        var query = ""
    }
    #endif

    @InjectedObject(\.userSessionManager)
    private var userSessionManager

    #if os(tvOS)
    @ObservedObject
    private var topShelfDeepLinkStore = TopShelfDeepLinkStore.shared
    #endif

    #if os(iOS)
    @StateObject
    private var tabCoordinator = TabCoordinator {
        TabItem.home
        TabItem.library(
            id: "tv-shows",
            title: L10n.tvShowsCapitalized,
            systemName: "tv",
            filters: .init(itemTypes: [.series]),
            showsGenreFilter: true
        )
        TabItem.library(
            id: "movies",
            title: L10n.movies,
            systemName: "film",
            filters: .init(itemTypes: [.movie]),
            showsGenreFilter: true
        )
        TabItem.media
        TabItem.search
    }

    @StateObject
    private var searchQueryState = SearchQueryState()
    #else
    @StateObject
    private var tabCoordinator = TabCoordinator {
        TabItem.home
        TabItem.library(
            title: L10n.tvShowsCapitalized,
            systemName: "tv",
            filters: .init(itemTypes: [.series])
        )
        TabItem.library(
            title: L10n.movies,
            systemName: "film",
            filters: .init(itemTypes: [.movie])
        )
        TabItem.search
        TabItem.media
        TabItem.settings
    }
    #endif

    private func routePendingDeepLink() {
        guard let deepLink = userSessionManager.consumePendingDeepLink() else { return }

        Task { @MainActor in
            let route = deepLink.route()
            await tabCoordinator.route(to: route)
        }
    }

    @ViewBuilder
    private func tabContent(for id: String) -> some View {
        if let tab = tabCoordinator.tabs.first(where: { $0.item.id == id }) {
            NavigationInjectionView(
                coordinator: tab.coordinator
            ) {
                tab.item.content
            }
            .environmentObject(tabCoordinator)
            #if os(iOS)
                .environmentObject(searchQueryState)
            #endif
                .environment(\.tabItemSelected, tab.publisher)
        }
    }

    private var legacyTabView: some View {
        TabView(selection: $tabCoordinator.selectedTabID) {
            ForEach(tabCoordinator.tabs, id: \.item.id) { tab in
                tabContent(for: tab.item.id)
                    .tabItem {
                        Label(
                            tab.item.title,
                            systemImage: tab.item.systemImage
                        )
                        .labelStyle(tab.item.labelStyle)
                        .symbolRenderingMode(.monochrome)
                        .eraseToAnyView()
                    }
                    .tag(tab.item.id)
            }
        }
    }

    #if os(iOS)
    @available(iOS 26.0, *)
    private var nativeTabView: some View {
        TabView(selection: $tabCoordinator.selectedTabID) {
            if UIDevice.isPad {
                Tab(L10n.home, systemImage: "house", value: "home") {
                    tabContent(for: "home")
                }

                Tab(L10n.movies, systemImage: "film", value: "movies") {
                    tabContent(for: "movies")
                }

                Tab(L10n.tvShowsCapitalized, systemImage: "tv", value: "tv-shows") {
                    tabContent(for: "tv-shows")
                }

                Tab(L10n.media, systemImage: "rectangle.stack.fill", value: "media") {
                    tabContent(for: "media")
                }

                Tab(value: "search", role: .search) {
                    tabContent(for: "search")
                }
            } else {
                TabSection {
                    Tab(L10n.home, systemImage: "house", value: "home") {
                        tabContent(for: "home")
                    }

                    Tab(L10n.tvShowsCapitalized, systemImage: "tv", value: "tv-shows") {
                        tabContent(for: "tv-shows")
                    }

                    Tab(L10n.movies, systemImage: "film", value: "movies") {
                        tabContent(for: "movies")
                    }

                    Tab(L10n.media, systemImage: "rectangle.stack.fill", value: "media") {
                        tabContent(for: "media")
                    }
                }

                Tab(value: "search", role: .search) {
                    tabContent(for: "search")
                }
            }
        }
        .if(!UIDevice.isPad) { tabView in
            NativeSearchTabView(searchQueryState: searchQueryState) {
                tabView
            }
        }
    }
    #endif

    @ViewBuilder
    private var selectedTabView: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            nativeTabView
        } else {
            legacyTabView
        }
        #else
        legacyTabView
        #endif
    }

    var body: some View {
        selectedTabView
            .onAppear {
                routePendingDeepLink()
            }
            .onReceive(userSessionManager.$pendingDeepLink.compactMap(\.self)) { _ in
                routePendingDeepLink()
            }
        #if os(tvOS)
            .task(id: topShelfDeepLinkStore.pendingURL) {
                await processTopShelfDeepLink()
            }
        #endif
    }

    #if os(tvOS)
    @MainActor
    private func processTopShelfDeepLink() async {
        guard let url = topShelfDeepLinkStore.pendingURL,
              let destination = topShelfDeepLinkStore.destination(for: url)
        else {
            return
        }

        defer {
            topShelfDeepLinkStore.consume(url)
        }

        guard let userSession = Container.shared.currentUserSession(),
              userSession.user.id == destination.userID
        else {
            return
        }

        let request = Paths.getItem(
            itemID: destination.itemID,
            userID: userSession.user.id
        )

        guard let response = try? await userSession.client.send(request),
              let homeTab = tabCoordinator.tabs.first(where: { $0.item.id == TabItem.home.id })
        else {
            return
        }

        tabCoordinator.selectedTabID = homeTab.item.id

        switch destination.action {
        case .display:
            homeTab.coordinator.push(.item(item: response.value))
        case .play:
            PlayMediaAction { homeTab.coordinator.push($0) }(item: response.value)
        }
    }
    #endif
}

#if os(iOS)
@available(iOS 26.0, *)
private struct NativeSearchTabView<Content: View>: View {

    @ObservedObject
    private var searchQueryState: MainTabView.SearchQueryState

    @FocusState
    private var isSearchFocused: Bool

    private let content: Content

    init(
        searchQueryState: MainTabView.SearchQueryState,
        @ViewBuilder content: () -> Content
    ) {
        self.searchQueryState = searchQueryState
        self.content = content()
    }

    var body: some View {
        content
            .searchable(text: $searchQueryState.query, prompt: L10n.search)
            .tabViewSearchActivation(.searchTabSelection)
            .searchFocused($isSearchFocused)
            .onSubmit(of: .search) {
                isSearchFocused = false
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button(L10n.done) {
                        isSearchFocused = false
                    }
                }
            }
    }
}
#endif
