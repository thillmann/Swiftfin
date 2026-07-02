//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftUI

struct BrowseByOptionView: View {

    let option: BrowseByOption

    @Router
    private var router

    @StateObject
    private var viewModel: BrowseByOptionViewModel

    @State
    private var pendingRequestItem: SeerrClient.MediaResult?

    private var hasNoItems: Bool {
        viewModel.items.isEmpty
    }

    init(option: BrowseByOption) {
        self.option = option
        _viewModel = StateObject(wrappedValue: BrowseByOptionViewModel(option: option))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let error = viewModel.error, hasNoItems {
                    ErrorView(error: error)
                } else if viewModel.isLoadingInitialPage, hasNoItems {
                    ProgressView()
                } else if hasNoItems {
                    ContentUnavailableView(L10n.noItems, systemImage: systemImage)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 56) {
                            header

                            UnifiedMediaGridSection(
                                title: nil,
                                items: viewModel.items,
                                containerWidth: proxy.size.width,
                                onNeedsNextPage: { item in
                                    viewModel.loadNextPageIfNeeded(currentItem: item)
                                },
                                onSelect: select
                            )

                            if viewModel.isLoadingNextPage {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            }
                        }
                        .padding(.top, 90)
                        .padding(.bottom, 90)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await viewModel.loadInitialPage()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .fullScreenCover(item: $pendingRequestItem) { item in
            SeerrRequestView(item: item) {
                viewModel.markRequested(item)
            }
        }
        .ignoresSafeArea()
    }

    private var systemImage: String {
        switch option.kind {
        case .movieStudio:
            "film"
        case .tvNetwork:
            "tv"
        }
    }

    private var header: some View {
        BrowseByLogoView(
            option: option,
            alignment: .center,
            foregroundColor: .white,
            accessibilityLabel: option.name
        )
        .frame(
            width: option.displayLogo.frameSize.width,
            height: option.displayLogo.frameSize.height
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 80)
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

extension BrowseByOptionView {

    @MainActor
    final class BrowseByOptionViewModel: ViewModel, SeerrRequestStateUpdating {

        @Published
        private(set) var items: [UnifiedMediaResult] = []

        @Published
        private(set) var error: SeerrClient.ProbeError?

        @Published
        private(set) var isLoadingInitialPage = false

        @Published
        private(set) var isLoadingNextPage = false

        private let option: BrowseByOption
        private var rawItems: [SeerrClient.MediaResult] = []
        private var nextPage = 1
        private var hasNextPage = true
        private let releaseDateParser: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        init(option: BrowseByOption) {
            self.option = option
        }

        func loadInitialPage() async {
            guard rawItems.isEmpty else { return }

            isLoadingInitialPage = true
            defer { isLoadingInitialPage = false }

            await resetAndLoadFirstPage()
        }

        func refresh() async {
            isLoadingInitialPage = true
            defer { isLoadingInitialPage = false }

            await resetAndLoadFirstPage()
        }

        func loadNextPageIfNeeded(currentItem: UnifiedMediaResult) {
            guard shouldLoadNextPage(currentItem: currentItem) else { return }

            Task {
                await loadNextPage()
            }
        }

        func markRequested(_ requestedItem: SeerrClient.MediaResult) {
            rawItems = SeerrLibraryMatcher.updatingRequestStatus(
                in: rawItems,
                for: requestedItem,
                to: .pending
            )

            Task {
                items = await SeerrLibraryMatcher.unifiedResults(for: rawItems, using: self)
            }
        }

        private func resetAndLoadFirstPage() async {
            error = nil
            rawItems = []
            items = []
            nextPage = 1
            hasNextPage = true

            await loadNextPage()
        }

        private func loadNextPage() async {
            guard hasNextPage, !isLoadingNextPage else { return }

            isLoadingNextPage = true
            defer { isLoadingNextPage = false }

            let page = nextPage
            let result = await option.kind.discover(
                optionID: option.seerrID,
                page: page,
                language: "en"
            )

            switch result {
            case let .success(response):
                nextPage += 1
                hasNextPage = page < (response.totalPages ?? page)
                appendRawItems(filtered(response.results))
                items = await SeerrLibraryMatcher.unifiedResults(for: rawItems, using: self)
            case let .failure(error):
                self.error = error
                hasNextPage = false
            }
        }

        private func appendRawItems(_ newItems: [SeerrClient.MediaResult]) {
            var knownIDs = Set(rawItems.map { SeerrLibraryMatcher.key(for: $0) })
            let uniqueItems = newItems.filter { item in
                knownIDs.insert(SeerrLibraryMatcher.key(for: item)).inserted
            }

            rawItems += uniqueItems
        }

        private func filtered(_ results: [SeerrClient.MediaResult]) -> [SeerrClient.MediaResult] {
            results.filter { item in
                guard item.mediaType == option.kind.mediaType, item.originalLanguage == "en" else { return false }
                guard let releaseDate = (item.releaseDate ?? item.firstAirDate).flatMap(releaseDateParser.date(from:)) else {
                    return false
                }

                return releaseDate <= Date()
            }
        }

        private func shouldLoadNextPage(currentItem: UnifiedMediaResult) -> Bool {
            guard hasNextPage, !isLoadingNextPage else { return false }
            guard let index = items.firstIndex(of: currentItem) else { return false }

            let thresholdIndex = items.index(
                items.endIndex,
                offsetBy: -6,
                limitedBy: items.startIndex
            ) ?? items.startIndex

            return index >= thresholdIndex
        }
    }
}
