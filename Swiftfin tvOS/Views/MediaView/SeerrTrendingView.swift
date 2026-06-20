//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftUI

struct SeerrTrendingView: View {

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
                ContentUnavailableView(L10n.noItems, systemImage: "chart.line.uptrend.xyaxis")
            } else {
                content
            }
        }
        .ignoresSafeArea()
        .refreshable {
            await viewModel.refresh()
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
        .navigationTitle(L10n.trending)
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

extension SeerrTrendingView {

    @MainActor
    final class ViewModel: ObservableObject {

        @Published
        private(set) var items: [UnifiedSearchResult] = []

        @Published
        private(set) var error: SeerrClient.ProbeError?

        @Published
        private(set) var isLoading = false

        private var results: [SeerrClient.MediaResult] = []
        private var mediaType = MediaType.movies

        private let pageLimit = 10
        private let releaseDateParser: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        func select(_ mediaType: MediaType) async {
            self.mediaType = mediaType
            updateItems()

            if results.isEmpty {
                await load()
            }
        }

        func refresh() async {
            await load()
        }

        func markRequested(_ requestedItem: SeerrClient.MediaResult) {
            results = results.map { item in
                guard item.id == requestedItem.id, item.mediaType == requestedItem.mediaType else { return item }
                return item.updatingStatus(.pending)
            }
            updateItems()
        }

        private func load() async {
            guard !isLoading else { return }

            isLoading = true
            error = nil
            defer { isLoading = false }

            let firstPageResult = await SeerrClient.discoverTrending(page: 1, language: "en")

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
                    let result = await SeerrClient.discoverTrending(page: page, language: "en")

                    switch result {
                    case let .success(response):
                        newResults.append(contentsOf: response.results)
                    case let .failure(error):
                        self.error = error
                        return
                    }
                }
            }

            results = filteredResults(newResults)
            updateItems()
        }

        private func filteredResults(_ results: [SeerrClient.MediaResult]) -> [SeerrClient.MediaResult] {
            var seenIDs = Set<String>()

            return results.filter { item in
                guard item.originalLanguage == "en", isReleased(item) else { return false }
                guard let mediaType = item.mediaType, mediaType != .person else { return false }

                return seenIDs.insert("\(mediaType.rawValue)-\(item.id)").inserted
            }
        }

        private func isReleased(_ item: SeerrClient.MediaResult) -> Bool {
            guard let value = item.releaseDate ?? item.firstAirDate,
                  let releaseDate = releaseDateParser.date(from: value)
            else {
                return false
            }

            return releaseDate <= Date()
        }

        private func updateItems() {
            let seerrMediaType: SeerrClient.MediaResult.MediaType = switch mediaType {
            case .movies:
                .movie
            case .tv:
                .tv
            }

            items = results
                .filter { $0.mediaType == seerrMediaType }
                .map(UnifiedSearchResult.seer)
        }
    }
}
