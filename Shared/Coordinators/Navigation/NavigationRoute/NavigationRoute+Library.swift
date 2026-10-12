//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension NavigationRoute {

    static func library(
        viewModel: PlatformPagingLibraryViewModel<some PlatformPoster>
    ) -> NavigationRoute {
        NavigationRoute(
            id: "library-(\(viewModel.parent?.id ?? "Unparented"))",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            PlatformPagingLibraryView(viewModel: viewModel)
        }
    }

    static func filter(type: ItemFilterType, viewModel: FilterViewModel) -> NavigationRoute {
        NavigationRoute(
            id: "filter",
            style: .sheet
        ) {
            FilterView(
                viewModel: viewModel,
                type: type
            )
        }
    }

    @MainActor
    static func contentGroup(
        provider: some ContentGroupProvider
    ) -> NavigationRoute {
        NavigationRoute(
            id: "content-group-\(provider.id)",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            ContentGroupView(provider: provider)
        }
    }

    @MainActor
    static func library<Library: PagingLibrary>(
        library: Library,
        displayTitle: String? = nil
    ) -> NavigationRoute where Library.Element: LibraryElement {
        NavigationRoute(
            id: "library-\(library.parent.pagingLibraryID)",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            PagingLibraryView(library: library, displayTitle: displayTitle)
        }
    }

    #if os(tvOS)
    static func genreLibrary(
        genre: MediaGenre,
        itemTypes: [BaseItemKind] = [.movie, .series]
    ) -> NavigationRoute {
        let itemTypeID = itemTypes
            .map { String(describing: $0) }
            .joined(separator: "-")

        return NavigationRoute(
            id: "genre-library-(\(genre.id))-(\(itemTypeID))",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            GenreLibraryView(genre: genre, itemTypes: itemTypes)
        }
    }
    #endif
}
