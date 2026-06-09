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

struct LazyPosterVGrid<Element: Poster>: View {

    @ObservedObject
    private var data: LazyLibraryCollection<Element>

    @State
    private var error: Error?

    @Default(.Customization.Indicators.showPlayed)
    private var showPlayed
    @Default(.Customization.Indicators.showUnplayed)
    private var showUnplayed
    @Default(.Customization.Indicators.showFavorited)
    private var showFavorited
    @Default(.Customization.Indicators.showProgress)
    private var showProgress

    private let columnCount: Int
    private let posterType: PosterDisplayType
    private let onSelect: (Element) -> Void

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 40), count: columnCount)
    }

    private var overlayOptions: MyPosterButtonOverlayOptions {
        var options: MyPosterButtonOverlayOptions = []
        if showPlayed {
            options.insert(.watched)
        }
        if showUnplayed != .none {
            options.insert(.unwatched)
        }
        if showFavorited {
            options.insert(.favorite)
        }
        if showProgress {
            options.insert(.progress)
        }
        return options
    }

    init(
        data: LazyLibraryCollection<Element>,
        posterType: PosterDisplayType = .portrait,
        columnCount: Int = 6,
        onSelect: @escaping (Element) -> Void
    ) {
        self.data = data
        self.posterType = posterType
        self.columnCount = columnCount
        self.onSelect = onSelect
    }

    private func cell(for item: Element) -> some View {
        MyPosterButton(
            item: item,
            type: posterType,
            overlayOptions: overlayOptions,
            unplayedIndicatorType: showUnplayed
        ) {
            onSelect(item)
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 40) {
                ForEach(data, id: \.unwrappedIDHashOrZero) { item in
                    cell(for: item)
                        .onAppear {
                            scheduleLoadMoreIfNeeded(currentItem: item)
                        }
                }
            }
            .padding(80)
            .padding(.top, 120)

            if data.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .padding(.vertical)
            }

            if let error {
                Text(error.localizedDescription)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
            }
        }
        .task {
            await loadInitialPage()
        }
    }

    private func scheduleLoadMoreIfNeeded(currentItem: Element) {
        Task {
            await loadMoreIfNeeded(currentItem: currentItem)
        }
    }

    private func loadInitialPage() async {
        guard data.isEmpty else { return }

        do {
            try await data.loadInitialPages()
        } catch {
            self.error = error
        }
    }

    private func loadMoreIfNeeded(currentItem: Element) async {
        do {
            try await data.loadNextPageIfNeeded(
                currentItem: currentItem,
                prefetchItemCount: data.pageSize,
                matches: { item, currentItem in
                    item.unwrappedIDHashOrZero == currentItem.unwrappedIDHashOrZero
                }
            )
        } catch {
            self.error = error
        }
    }
}

private struct MyPosterButton<Item: Poster>: View {
    let item: Item
    let posterType: PosterDisplayType
    let overlayOptions: MyPosterButtonOverlayOptions
    let unplayedIndicatorType: UnplayedIndicatorType
    private let action: () -> Void

    init(
        item: Item,
        type: PosterDisplayType,
        overlayOptions: MyPosterButtonOverlayOptions,
        unplayedIndicatorType: UnplayedIndicatorType,
        action: @escaping () -> Void
    ) {
        self.item = item
        self.posterType = type
        self.overlayOptions = overlayOptions
        self.unplayedIndicatorType = unplayedIndicatorType
        self.action = action
    }

    var body: some View {
        Button {
            action()
        } label: {
            PosterButtonContent(
                item: item,
                posterType: posterType,
                overlayOptions: overlayOptions,
                unplayedIndicatorType: unplayedIndicatorType
            )
        }
        .buttonStyle(.card)
    }
}

private struct MyPosterButtonOverlayOptions: OptionSet {
    let rawValue: Int

    static let watched = Self(rawValue: 1 << 0)
    static let favorite = Self(rawValue: 1 << 1)
    static let progress = Self(rawValue: 1 << 2)
    static let unwatched = Self(rawValue: 1 << 3)

    static let `default`: Self = [
        .watched,
        .unwatched,
        .favorite,
        .progress,
    ]
}

private struct PosterButtonContent<Item: Poster>: View {
    @Environment(\.isFocused)
    private var isFocused

    let item: Item
    let posterType: PosterDisplayType
    let overlayOptions: MyPosterButtonOverlayOptions
    let unplayedIndicatorType: UnplayedIndicatorType

    private var baseItem: BaseItemDto? {
        item as? BaseItemDto
    }

    private var isPlayed: Bool {
        baseItem?.userData?.isPlayed == true ||
            (baseItem?.userData?.playedPercentage ?? 0) >= 100
    }

    private var playbackProgress: Double {
        baseItem?.userData?.playedPercentage ?? 0.0
    }

    private var hasPlaybackProgress: Bool {
        (baseItem?.userData?.playbackPositionTicks ?? 0) > 0
    }

    private var canShowStatusIndicator: Bool {
        baseItem?.canBePlayed == true && baseItem?.isLiveStream != true
    }

    private var isWatchedBranch: Bool {
        canShowStatusIndicator && isPlayed
    }

    private var isProgressBranch: Bool {
        !isWatchedBranch && hasPlaybackProgress
    }

    private var isUnwatchedBranch: Bool {
        canShowStatusIndicator &&
            !isWatchedBranch &&
            !isProgressBranch
    }

    @ViewBuilder
    private var playOverlay: some View {
        Image(systemName: isPlayed ? "arrow.counterclockwise" : "play.fill")
            .font(.caption2)
            .foregroundStyle(.white)
            .opacity(isFocused ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.18), value: isFocused)
    }

    @ViewBuilder
    private var favoritedOverlay: some View {
        VStack {
            HStack {
                Spacer(minLength: 0)
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(12)
                    .opacity(isFocused ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.18), value: isFocused)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        ProgressView(value: playbackProgress / 100)
            .progressViewStyle(
                FeatureInlineProgressStyle(
                    trackColor: .white.opacity(0.2),
                    fillColor: .white.opacity(1)
                )
            )
            .frame(width: 40)
            .opacity(isFocused ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.18), value: isFocused)
    }

    @ViewBuilder
    private var unwatchedCountOverlay: some View {
        if unplayedIndicatorType == .count,
           let count = baseItem?.userData?.unplayedItemCount,
           count > 0
        {
            Text(count.description)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: 21)
                .frame(minWidth: 21)
                .background(.black.opacity(0.55), in: Capsule())
                .opacity(isFocused ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }

    private var shouldShowWatchedOverlay: Bool {
        isWatchedBranch &&
            overlayOptions.contains(.watched)
    }

    private var shouldShowProgressOverlay: Bool {
        isProgressBranch &&
            overlayOptions.contains(.progress)
    }

    private var shouldShowUnwatchedOverlay: Bool {
        isUnwatchedBranch &&
            overlayOptions.contains(.unwatched)
    }

    private var shouldShowBottomOverlay: Bool {
        shouldShowWatchedOverlay ||
            shouldShowProgressOverlay ||
            shouldShowUnwatchedOverlay
    }

    @ViewBuilder
    private var bottomBackdrop: some View {
        LinearGradient(
            colors: [
                .clear,
                .black.opacity(0.34),
                .black.opacity(0.5),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.85),
                            .black,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .opacity(isFocused ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: isFocused)
    }

    @ViewBuilder
    private func bottomContent(
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack {
            Spacer(minLength: 0)

            ZStack(alignment: .bottom) {
                bottomBackdrop

                HStack(alignment: .center, spacing: 12) {
                    content()

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var body: some View {
        ZStack {
            PosterImage(
                item: item,
                type: posterType,
                prefersBlurHashPlaceholder: false
            )

            if overlayOptions.contains(.favorite) && baseItem?.userData?.isFavorite == true {
                favoritedOverlay
            }

            if shouldShowBottomOverlay {
                bottomContent {
                    playOverlay

                    if shouldShowProgressOverlay {
                        progressOverlay
                    } else if shouldShowUnwatchedOverlay {
                        unwatchedCountOverlay
                    }
                }
            }
        }
    }
}
