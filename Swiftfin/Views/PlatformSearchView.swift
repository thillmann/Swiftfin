//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

// TODO: have a `SearchLibraryViewModel` that allows paging on searched items?
// TODO: implement search view result type between `PlatformPosterHStack`
//       and `ListHStack` (3 row list columns)? (iOS only)
// TODO: have programs only pull recommended/current?
//       - have progress overlay
struct PlatformSearchView: View {

    private static let iPadSearchFieldHeight: CGFloat = 64

    private struct GenrePalette {
        let background: [Color]
        let tint: Color
        let glow: Color
    }

    @Default(.Customization.Search.enabledDrawerFilters)
    private var enabledDrawerFilters
    @Default(.Customization.searchPosterType)
    private var searchPosterType

    @Router
    private var router

    @PlayMedia
    private var playMedia

    #if os(iOS)
    @EnvironmentObject
    private var searchQueryState: MainTabView.SearchQueryState
    @FocusState
    private var isIPadSearchFocused: Bool
    #endif

    #if os(tvOS)
    @FocusState
    private var isSearchFocused: Bool
    @State
    private var localSearchQuery = ""
    @TabItemSelected
    private var tabItemSelected
    #endif

    @StateObject
    private var viewModel = PlatformSearchViewModel(filterViewModel: .init())
    @State
    private var pendingSeerRequestItem: SeerrClient.MediaResult?

    #if os(tvOS)
    private var searchQuery: Binding<String> {
        $localSearchQuery
    }
    #endif

    @ViewBuilder
    private var genreBrowseView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                genreSection(
                    title: L10n.movies,
                    genres: GenreTaxonomy.movieGenres,
                    itemTypes: [.movie]
                )

                genreSection(
                    title: L10n.tvShows,
                    genres: GenreTaxonomy.tvShowGenres,
                    itemTypes: [.series]
                )
            }
            .edgePadding(.horizontal)
            #if os(iOS)
                .padding(.top, UIDevice.isPad ? Self.iPadSearchFieldHeight + 12 : 12)
                .edgePadding(.bottom)
            #else
                .edgePadding(.vertical)
            #endif
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func genreSection(
        title: String,
        genres: [MediaGenre],
        itemTypes: [BaseItemKind]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 12),
                    count: genreColumnCount
                ),
                spacing: 12
            ) {
                ForEach(genres) { genre in
                    genreButton(genre, itemTypes: itemTypes)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var genreColumnCount: Int {
        #if os(iOS)
        if UIDevice.isPad {
            let isLandscape = UIApplication.shared.keyWindow?.bounds.size.isLandscape == true
            return isLandscape ? 6 : 5
        }
        #endif

        return 3
    }

    @ViewBuilder
    private func genreButton(
        _ genre: MediaGenre,
        itemTypes: [BaseItemKind]
    ) -> some View {
        if #available(iOS 26.0, *) {
            genreButtonContent(genre, itemTypes: itemTypes)
                .buttonStyle(.plain)
        } else {
            genreButtonContent(genre, itemTypes: itemTypes)
                .buttonStyle(.card)
        }
    }

    private func genreButtonContent(
        _ genre: MediaGenre,
        itemTypes: [BaseItemKind]
    ) -> some View {
        Button {
            let itemTypeID = itemTypes
                .map { String(describing: $0) }
                .joined(separator: "-")
            let viewModel = ItemLibraryViewModel(
                title: genre.displayTitle,
                id: "search-genre-\(genre.id)-\(itemTypeID)",
                matchingAnyGenre: genre.jellyfinGenres,
                itemTypes: itemTypes
            )
            router.route(to: .library(viewModel: viewModel))
        } label: {
            genrePosterContent(for: genre)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(genre.displayTitle)
    }

    @ViewBuilder
    private func genrePosterContent(for genre: MediaGenre) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let content = ZStack(alignment: .bottomLeading) {
            genreArtwork(for: genre)

            Text(genre.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(12)
        }
        .posterAspectRatio(.portrait)
        .contentShape(.contextMenuPreview, Rectangle())
        .containerShape(shape)

        if #available(iOS 26.0, *) {
            content
                .glassEffect(.clear, in: shape)
                .clipShape(shape)
        } else {
            content
                .clipShape(shape)
                .overlay {
                    shape
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
        }
    }

    private func genreArtwork(for genre: MediaGenre) -> some View {
        let palette = genrePalette(for: genre)

        return ZStack {
            if genre.artworkImageSources.isNotEmpty {
                GeometryReader { proxy in
                    ImageView(genre.artworkImageSources)
                        .image { image in
                            image
                                .aspectRatio(contentMode: .fill)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                        }
                        .placeholder { _ in
                            abstractGenreArtwork(palette: palette)
                        }
                        .failure {
                            abstractGenreArtwork(palette: palette)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            } else {
                abstractGenreArtwork(palette: palette)
            }

            RadialGradient(
                colors: [
                    palette.glow.opacity(0.85),
                    palette.glow.opacity(0.18),
                    .clear,
                ],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 260
            )
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    palette.tint.opacity(0.72),
                    palette.tint.opacity(0.18),
                    .clear,
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )

            LinearGradient(
                colors: [
                    .black.opacity(0.05),
                    .black.opacity(0.34),
                    .black.opacity(0.82),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func abstractGenreArtwork(palette: GenrePalette) -> some View {
        LinearGradient(
            colors: palette.background,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func genrePalette(for genre: MediaGenre) -> GenrePalette {
        switch genre.id {
        case "action", "action-adventure":
            .init(background: [.orange, .red, .black], tint: .orange, glow: .yellow)
        case "adventure":
            .init(background: [.mint, .green, .black], tint: .green, glow: .cyan)
        case "animation":
            .init(background: [.cyan, .purple, .pink], tint: .pink, glow: .yellow)
        case "comedy":
            .init(background: [.yellow, .green, .black], tint: .green, glow: .yellow)
        case "crime":
            .init(background: [.gray, .blue, .black], tint: .blue, glow: .cyan)
        case "documentary":
            .init(background: [.teal, .blue, .black], tint: .teal, glow: .mint)
        case "drama":
            .init(background: [.blue, .indigo, .black], tint: .blue, glow: .cyan)
        case "family", "kids", "kids-family":
            .init(background: [.pink, .orange, .purple], tint: .pink, glow: .yellow)
        case "fantasy":
            .init(background: [.purple, .indigo, .black], tint: .purple, glow: .mint)
        case "history":
            .init(background: [.brown, .orange, .black], tint: .orange, glow: .yellow)
        case "horror":
            .init(background: [.orange, .black, .black], tint: .orange, glow: .red)
        case "music":
            .init(background: [.pink, .purple, .black], tint: .pink, glow: .cyan)
        case "mystery":
            .init(background: [.indigo, .gray, .black], tint: .indigo, glow: .blue)
        case "news", "talk":
            .init(background: [.blue, .cyan, .black], tint: .blue, glow: .white)
        case "politics", "war", "war-politics":
            .init(background: [.gray, .red, .black], tint: .red, glow: .orange)
        case "reality":
            .init(background: [.purple, .pink, .black], tint: .purple, glow: .pink)
        case "romance":
            .init(background: [.pink, .red, .black], tint: .pink, glow: .orange)
        case "science-fiction", "sci-fi-fantasy":
            .init(background: [.cyan, .indigo, .black], tint: .cyan, glow: .teal)
        case "soap":
            .init(background: [.mint, .teal, .black], tint: .teal, glow: .white)
        case "thriller":
            .init(background: [.red, .purple, .black], tint: .red, glow: .orange)
        case "western":
            .init(background: [.orange, .brown, .black], tint: .brown, glow: .yellow)
        default:
            .init(background: [.teal, .purple, .black], tint: .teal, glow: .white)
        }
    }

    @ViewBuilder
    private var resultsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if let movies = viewModel.unifiedItems[.movie], movies.isNotEmpty {
                    unifiedItemsSection(
                        title: L10n.movies,
                        type: .movie,
                        items: movies,
                        posterType: searchPosterType
                    )
                }

                if let series = viewModel.unifiedItems[.series], series.isNotEmpty {
                    unifiedItemsSection(
                        title: L10n.tvShows,
                        type: .series,
                        items: series,
                        posterType: searchPosterType
                    )
                }

                if let collections = viewModel.items[.boxSet], collections.isNotEmpty {
                    itemsSection(
                        title: L10n.collections,
                        type: .boxSet,
                        items: collections,
                        posterType: searchPosterType
                    )
                }

                if let episodes = viewModel.items[.episode], episodes.isNotEmpty {
                    episodeItemsSection(episodes)
                }

                if let musicVideos = viewModel.items[.musicVideo], musicVideos.isNotEmpty {
                    itemsSection(
                        title: L10n.musicVideos,
                        type: .musicVideo,
                        items: musicVideos,
                        posterType: .landscape
                    )
                }

                if let videos = viewModel.items[.video], videos.isNotEmpty {
                    itemsSection(
                        title: L10n.videos,
                        type: .video,
                        items: videos,
                        posterType: .landscape
                    )
                }

                if let programs = viewModel.items[.program], programs.isNotEmpty {
                    itemsSection(
                        title: L10n.programs,
                        type: .program,
                        items: programs,
                        posterType: .landscape
                    )
                }

                if let channels = viewModel.items[.tvChannel], channels.isNotEmpty {
                    itemsSection(
                        title: L10n.channels,
                        type: .tvChannel,
                        items: channels,
                        posterType: .square
                    )
                }

                if let musicArtists = viewModel.items[.musicArtist], musicArtists.isNotEmpty {
                    itemsSection(
                        title: L10n.artists,
                        type: .musicArtist,
                        items: musicArtists,
                        posterType: .portrait
                    )
                }

                if let people = viewModel.unifiedItems[.person], people.isNotEmpty {
                    unifiedItemsSection(
                        title: L10n.people,
                        type: .person,
                        items: people,
                        posterType: .portrait
                    )
                }
            }
            .edgePadding(.vertical)
            #if os(iOS)
                .padding(.top, UIDevice.isPad ? Self.iPadSearchFieldHeight : 0)
            #endif
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func select(_ item: BaseItemDto, in namespace: Namespace.ID) {
        switch item.type {
        case .program, .tvChannel:
            guard let userSession = viewModel.userSession else { return }
            guard let intent = item.getPlaybackIntent(userSession: userSession) else { return }

            playMedia(intent: intent)

        default:
            router.route(to: .item(item: item), in: namespace)
        }
    }

    private func select(_ item: UnifiedMediaResult, in namespace: Namespace.ID) {
        switch item {
        case let .jellyfin(baseItem):
            select(baseItem, in: namespace)
        case let .seerr(seerItem):
            pendingSeerRequestItem = seerItem
        }
    }

    @ViewBuilder
    private func itemsSection(
        title: String,
        type: BaseItemKind,
        items: [BaseItemDto],
        posterType: PosterDisplayType
    ) -> some View {
        PlatformPosterHStack(
            title: title,
            type: posterType,
            items: items,
            headerAction: {
                let viewModel = PlatformPagingLibraryViewModel(
                    title: title,
                    id: "search-\(type.hashValue)",
                    items
                )
                router.route(to: .library(viewModel: viewModel))
            },
            action: select
        )
    }

    @ViewBuilder
    private func episodeItemsSection(_ episodes: [BaseItemDto]) -> some View {
        PlatformPosterHStack(
            title: L10n.episodes,
            type: .landscape,
            items: episodes,
            headerAction: {
                let viewModel = PlatformPagingLibraryViewModel(
                    title: L10n.episodes,
                    id: "search-\(BaseItemKind.episode.hashValue)",
                    episodes
                )
                router.route(to: .library(viewModel: viewModel))
            }
        ) { episode in
            SeriesEpisodeSelector.EpisodeCard(episode: episode)
        }
        .itemColumnCount(UIDevice.isPhone ? 1.5 : 3.5)
        .itemContentAspectRatio(EpisodeCardLayout.artworkAspectRatio)
        .itemLabelHeight(
            EpisodeCardLayout.footerHeight
                - EpisodeCardLayout.fadeOverlap
                - PosterButtonLayout.landscapeFooterHeight
        )
    }

    @ViewBuilder
    private func unifiedItemsSection(
        title: String,
        type: BaseItemKind,
        items: [UnifiedMediaResult],
        posterType: PosterDisplayType
    ) -> some View {
        PlatformPosterHStack(
            title: title,
            type: posterType,
            items: items,
            headerAction: {
                let viewModel = PlatformPagingLibraryViewModel(
                    title: title,
                    id: "search-\(type.hashValue)",
                    items
                )
                router.route(to: .library(viewModel: viewModel))
            },
            action: { item, namespace in
                select(item, in: namespace)
            }
        ) { item in
            PosterButtonTitleSubtitleContentView(item: item)
        }
        .posterOverlay(for: UnifiedMediaResult.self) { item in
            UnifiedMediaResultPosterOverlay(item: item)
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        ZStack {
            switch viewModel.state {
            case .error:
                viewModel.error.map {
                    ErrorView(error: $0)
                }

            case .initial:
                if viewModel.hasNoResults {
                    if viewModel.canSearch {
                        ContentUnavailableView.search
                    } else {
                        genreBrowseView
                    }
                } else {
                    resultsView
                }

            case .searching:
                if viewModel.hasNoResults {
                    ProgressView()
                        .allowsHitTesting(false)
                } else {
                    resultsView

                    ProgressView()
                        .padding(14)
                        .background(.regularMaterial, in: Circle())
                        .allowsHitTesting(false)
                }
            }
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var iPadSearchField: some View {
        let shape = Capsule(style: .continuous)
        let field = HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(L10n.search, text: $searchQueryState.query)
                .focused($isIPadSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    isIPadSearchFocused = false
                }

            if searchQueryState.query.isNotEmpty {
                Button {
                    searchQueryState.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity)

        Group {
            if #available(iOS 26.0, *) {
                field
                    .glassEffect(.regular, in: shape)
            } else {
                field
                    .background(.regularMaterial, in: shape)
            }
        }
        .edgePadding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
    #endif

    @ViewBuilder
    private var platformContent: some View {
        #if os(iOS)
        if UIDevice.isPad {
            ZStack(alignment: .top) {
                searchContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                iPadSearchField
                    .zIndex(1)
            }
        } else {
            searchContent
        }
        #else
        searchContent
        #endif
    }

    var body: some View {
        platformContent
            .animation(.linear(duration: 0.2), value: viewModel.state)
        #if os(tvOS)
            .navigationTitle(L10n.search)
        #endif
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                viewModel.refreshSearch()
            }
            .navigationBarFilterDrawer(
                viewModel: viewModel.filterViewModel,
                types: enabledDrawerFilters
            )
        #if os(iOS)
            .background {
                SearchQueryObserver { query in
                    viewModel.search(query: query)
                }
            }
        #endif
        #if os(tvOS)
            .searchable(
            text: searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: L10n.search
        )
        .backport
        .searchFocused($isSearchFocused)
        .onChange(of: searchQuery.wrappedValue) { newValue in
            viewModel.search(query: newValue)
        }
        .onReceive(tabItemSelected) { event in
            if event.isRepeat, event.isRoot {
                isSearchFocused = true
            }
        }
        #endif
        .sheet(item: $pendingSeerRequestItem) { item in
                SeerrRequestView(item: item) {
                    viewModel.refreshSearch()
                }
            }
    }
}

#if os(iOS)
private struct SearchQueryObserver: View {

    @EnvironmentObject
    private var searchQueryState: MainTabView.SearchQueryState

    let action: (String) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                action(searchQueryState.query)
            }
            .onChange(of: searchQueryState.query) { newValue in
                action(newValue)
            }
    }
}
#endif
