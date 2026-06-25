//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct SeerrUpcomingView: View {

    enum MediaType: Hashable {
        case movies
        case tv
    }

    @StateObject
    private var viewModel = ViewModel()

    @State
    private var pendingRequestItem: SeerrClient.MediaResult?

    @State
    private var selectedMediaType = MediaType.movies

    private var content: some View {
        PosterVGrid(
            data: viewModel.items,
            posterType: .portrait,
            columnCount: 6
        ) { item in
            if case let .seer(seerrItem) = item {
                pendingRequestItem = seerrItem
            }
        }
    }

    private var tabContent: some View {
        ZStack {
            if let error = viewModel.error, viewModel.items.isEmpty {
                ErrorView(error: error)
            } else if viewModel.isLoading, viewModel.items.isEmpty {
                ProgressView()
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(L10n.noUpcomingTitles, systemImage: "calendar")
            } else {
                content
            }
        }
        .ignoresSafeArea()
        .refreshable {
            await viewModel.refresh(mediaType: selectedMediaType)
        }
    }

    var body: some View {
        TabView(selection: $selectedMediaType) {
            tabContent
                .tabItem {
                    Label(L10n.movies, systemImage: "film")
                        .symbolRenderingMode(.monochrome)
                }
                .tag(MediaType.movies)

            tabContent
                .tabItem {
                    Label(L10n.tvShows, systemImage: "tv")
                        .symbolRenderingMode(.monochrome)
                }
                .tag(MediaType.tv)
        }
        .navigationTitle(L10n.upcoming)
        .task(id: selectedMediaType) {
            await viewModel.select(selectedMediaType)
        }
        .fullScreenCover(item: $pendingRequestItem) { item in
            SeerrRequestView(item: item) {
                viewModel.markRequested(item)
            }
        }
    }
}

extension SeerrUpcomingView {

    @MainActor
    final class ViewModel: ObservableObject {

        @Published
        private(set) var items: [UnifiedSearchResult] = []

        @Published
        private(set) var error: SeerrClient.ProbeError?

        @Published
        private(set) var isLoading = false

        private var results: [MediaType: [SeerrClient.MediaResult]] = [:]
        private var mediaType = MediaType.movies

        private let pageLimit = 5

        func select(_ mediaType: MediaType) async {
            self.mediaType = mediaType
            updateItems()
            error = nil

            if results[mediaType] == nil {
                isLoading = false
                await load(mediaType: mediaType)
            }
        }

        func refresh(mediaType: MediaType) async {
            await load(mediaType: mediaType)
        }

        func markRequested(_ requestedItem: SeerrClient.MediaResult) {
            results = results.mapValues { items in
                items.map { item in
                    guard item.id == requestedItem.id, item.mediaType == requestedItem.mediaType else { return item }
                    return item.updatingStatus(.pending)
                }
            }
            updateItems()
        }

        private func load(mediaType: MediaType) async {
            guard !isLoading else { return }

            isLoading = true
            error = nil
            defer {
                if self.mediaType == mediaType {
                    isLoading = false
                }
            }

            let firstPageResult = await discover(mediaType: mediaType, page: 1)
            guard self.mediaType == mediaType else { return }

            guard case let .success(firstPage) = firstPageResult else {
                if case let .failure(error) = firstPageResult {
                    self.error = error
                }
                return
            }

            var newResults = firstPage.results
            let lastPage = min(firstPage.totalPages ?? 1, pageLimit)

            if lastPage > 1 {
                for page in 2 ... lastPage {
                    let result = await discover(mediaType: mediaType, page: page)
                    guard self.mediaType == mediaType else { return }

                    switch result {
                    case let .success(response):
                        newResults.append(contentsOf: response.results)
                    case let .failure(error):
                        self.error = error
                        return
                    }
                }
            }

            results[mediaType] = deduplicated(
                newResults.filter { $0.originalLanguage == "en" }
            )
            updateItems()
        }

        private func deduplicated(_ results: [SeerrClient.MediaResult]) -> [SeerrClient.MediaResult] {
            var seenIDs = Set<String>()

            return results.filter { item in
                seenIDs.insert("\(item.mediaType?.rawValue ?? "unknown")-\(item.id)").inserted
            }
        }

        private func discover(
            mediaType: MediaType,
            page: Int
        ) async -> Result<SeerrClient.Page<SeerrClient.MediaResult>, SeerrClient.ProbeError> {
            switch mediaType {
            case .movies:
                await SeerrClient.discoverUpcomingMovies(page: page, language: "en")
            case .tv:
                await SeerrClient.discoverUpcomingTV(page: page, language: "en")
            }
        }

        private func sortByReleaseDate(_ items: [UnifiedSearchResult]) -> [UnifiedSearchResult] {
            items.sorted { lhs, rhs in
                let lhsDate = releaseDate(for: lhs)
                let rhsDate = releaseDate(for: rhs)

                switch (lhsDate, rhsDate) {
                case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                    return lhsDate < rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.id < rhs.id
                }
            }
        }

        private func releaseDate(for item: UnifiedSearchResult) -> String? {
            guard case let .seer(item) = item else { return nil }
            guard let date = item.releaseDate ?? item.firstAirDate, date.isNotEmpty else { return nil }
            return date
        }

        private func updateItems() {
            items = sortByReleaseDate(
                (results[mediaType] ?? [])
                    .map(UnifiedSearchResult.seer)
            )
        }
    }
}
