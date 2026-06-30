//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftUI

struct SeerrTrendingView: View {

    enum MediaType: Hashable {
        case movies
        case tv
    }

    @StateObject
    private var viewModel = TrendingViewModel()

    @Router
    private var router

    @State
    private var pendingRequestItem: SeerrClient.MediaResult?

    @State
    private var selectedMediaType = MediaType.movies

    private var hasNoItems: Bool {
        viewModel.inLibraryItems.isEmpty && viewModel.availableItems.isEmpty
    }

    private var tabContent: some View {
        ZStack {
            if let error = viewModel.error, hasNoItems {
                ErrorView(error: error)
            } else if viewModel.isLoading, hasNoItems {
                ProgressView()
            } else if hasNoItems {
                ContentUnavailableView(L10n.noItems, systemImage: "chart.line.uptrend.xyaxis")
            } else {
                contentView
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

    private var contentView: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 64) {
                    UnifiedMediaGridSection(
                        title: "In Library",
                        items: viewModel.inLibraryItems,
                        containerWidth: proxy.size.width,
                        onSelect: select
                    )

                    UnifiedMediaGridSection(
                        title: "Available",
                        items: viewModel.availableItems,
                        containerWidth: proxy.size.width,
                        onSelect: select
                    )
                }
                .padding(.top, 120)
                .padding(.bottom, 80)
            }
        }
    }

    private func select(_ item: UnifiedMediaResult) {
        switch item {
        case let .jellyfin(baseItem):
            router.route(to: .item(item: baseItem))
        case let .seerr(seerrItem):
            pendingRequestItem = seerrItem
        }
    }
}

extension SeerrTrendingView {

    @MainActor
    final class TrendingViewModel: ViewModel {

        @Published
        private(set) var inLibraryItems: [UnifiedMediaResult] = []

        @Published
        private(set) var availableItems: [UnifiedMediaResult] = []

        @Published
        private(set) var error: SeerrClient.ProbeError?

        @Published
        private(set) var isLoading = false

        private var results: [SeerrClient.MediaResult] = []
        private var libraryMatches: [String: BaseItemDto] = [:]
        private var mediaType = MediaType.movies

        private let resultLimit = 50
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

            let resultsPageResult = await getResultsPage()

            guard case let .success(pageResults) = resultsPageResult else {
                if case let .failure(error) = resultsPageResult { self.error = error }
                return
            }

            let filteredResults = filteredResults(pageResults)
            results = filteredResults
            libraryMatches = await libraryMatches(for: filteredResults)
            updateItems()
        }

        private func getResultsPage() async -> Result<[SeerrClient.MediaResult], SeerrClient.ProbeError> {
            let firstPageResult = await SeerrClient.discoverTrending(page: 1, language: "en")
            guard case let .success(firstPage) = firstPageResult else {
                if case let .failure(error) = firstPageResult { return .failure(error) }
                return .success([])
            }

            var results = Array(firstPage.results.prefix(resultLimit))
            let totalPages = firstPage.totalPages ?? 1

            guard totalPages > 1, results.count < resultLimit else { return .success(results) }

            for page in 2 ... totalPages {
                let pageResult = await SeerrClient.discoverTrending(page: page, language: "en")

                switch pageResult {
                case let .success(response):
                    results.append(contentsOf: response.results.prefix(resultLimit - results.count))

                    if results.count >= resultLimit {
                        return .success(results)
                    }
                case let .failure(error):
                    return .failure(error)
                }
            }

            return .success(results)
        }

        private func filteredResults(_ results: [SeerrClient.MediaResult]) -> [SeerrClient.MediaResult] {
            var seenIDs = Set<String>()

            return results.filter { item in
                guard item.originalLanguage == "en", isReleased(item) else { return false }
                guard let mediaType = item.mediaType, mediaType != .person else { return false }

                return seenIDs.insert(SeerrLibraryMatcher.key(for: item)).inserted
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

            let typedResults = results
                .filter { $0.mediaType == seerrMediaType }

            inLibraryItems = typedResults.compactMap { item in
                libraryMatches[SeerrLibraryMatcher.key(for: item)]
                    .map(UnifiedMediaResult.jellyfin)
            }

            availableItems = typedResults
                .filter { libraryMatches[SeerrLibraryMatcher.key(for: $0)] == nil }
                .map(UnifiedMediaResult.seerr)
        }

        private func libraryMatches(for results: [SeerrClient.MediaResult]) async -> [String: BaseItemDto] {
            var matches: [String: BaseItemDto] = [:]

            for result in results {
                guard let match = await libraryMatch(for: result) else { continue }
                matches[SeerrLibraryMatcher.key(for: result)] = match
            }

            return matches
        }

        private func libraryMatch(for result: SeerrClient.MediaResult) async -> BaseItemDto? {
            do {
                return try await SeerrLibraryMatcher.libraryMatch(for: result, using: self)
            } catch {
                return nil
            }
        }
    }
}
