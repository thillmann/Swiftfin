//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// TODO: selected icon
@MainActor
struct TabItem: Displayable, Identifiable, Hashable {

    var displayTitle: String {
        title
    }

    let content: AnyView
    let id: String
    let title: String
    let systemImage: String
    let labelStyle: any LabelStyle

    init(
        id: String,
        title: String,
        systemImage: String,
        labelStyle: some LabelStyle = .titleAndIcon,
        @ViewBuilder content: () -> some View
    ) {
        self.content = AnyView(content())
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.labelStyle = labelStyle
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

extension TabItem {

    static var home: TabItem {
        TabItem(
            id: "home",
            title: L10n.home,
            systemImage: "house"
        ) {
            HomeView()
        }
    }

    static func library(
        id: String? = nil,
        title: String,
        systemName: String,
        filters: ItemFilterCollection,
        showsGenreFilter: Bool = false
    ) -> TabItem {
        TabItem(
            id: id ?? "library-\(UUID().uuidString)",
            title: title,
            systemImage: systemName
        ) {
            let viewModel = ItemLibraryViewModel(
                filters: filters
            )

            #if os(iOS)
            PlatformPagingLibraryView(
                viewModel: viewModel,
                navigationTitle: title,
                showsGenreFilter: showsGenreFilter
            )
            #else
            PlatformPagingLibraryView(viewModel: viewModel)
            #endif
        }
    }

    static var media: TabItem {
        TabItem(
            id: "media",
            title: L10n.media,
            systemImage: "rectangle.stack.fill"
        ) {
            MediaView()
        }
    }

    static var search: TabItem {
        TabItem(
            id: "search",
            title: L10n.search,
            systemImage: "magnifyingglass"
        ) {
            PlatformSearchView()
        }
    }

    static var settings: TabItem {
        TabItem(
            id: "settings",
            title: L10n.settings,
            systemImage: "gearshape"
        ) {
            SettingsView()
        }
    }
}

extension TabItem {
    static var adminDashboard: TabItem {
        TabItem(
            id: "admin-dashboard",
            title: L10n.dashboard,
            systemImage: "server.rack"
        ) {
            #if os(iOS)
            AdminDashboardView()
            #else
            EmptyView()
            #endif
        }
    }

    static func contentGroup(
        provider: some ContentGroupProvider
    ) -> TabItem {
        TabItem(
            id: provider.id,
            title: provider.displayTitle,
            systemImage: "house.fill"
        ) {
            ContentGroupView(provider: provider)
        }
    }

    static func item(id: String, displayTitle: String) -> TabItem {
        let item = BaseItemDto(id: id, name: displayTitle)
        let provider = ItemContentGroupProvider(item: item)

        return TabItem(
            id: id,
            title: displayTitle,
            systemImage: item.systemImage
        ) {
            ItemView(provider: provider)
        }
    }

    static var liveTV: TabItem {
        TabItem(
            id: "live-tv",
            title: L10n.liveTV,
            systemImage: "play.tv"
        ) {
            NavigationRoute.liveTV.destination
        }
    }
}
