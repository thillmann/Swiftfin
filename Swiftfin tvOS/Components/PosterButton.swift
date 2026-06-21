//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension EnvironmentValues {

    @Entry
    var posterButtonOverlayOptions: PosterButtonOverlayOptions = .default

    @Entry
    var posterButtonUnplayedIndicatorType: UnplayedIndicatorType = .none
}

extension View {

    func posterOverlayOptions(
        _ options: PosterButtonOverlayOptions,
        unplayedIndicatorType: UnplayedIndicatorType
    ) -> some View {
        environment(\.posterButtonOverlayOptions, options)
            .environment(\.posterButtonUnplayedIndicatorType, unplayedIndicatorType)
    }

    func posterOverlayFocus(_ isFocused: Bool) -> some View {
        modifier(PosterOverlayFocusModifier(isFocused: isFocused))
    }
}

private struct PosterOverlayFocusModifier: ViewModifier {

    let isFocused: Bool

    @State
    private var isOverlayFocused = false
    @State
    private var focusTask: Task<Void, Never>?
    @State
    private var pendingFocusValue: Bool?

    func body(content: Content) -> some View {
        content
            .environment(\.isPosterFocused, isOverlayFocused)
            .onAppear {
                updateOverlayFocus(isFocused)
            }
            .onChange(of: isFocused) { _, newValue in
                updateOverlayFocus(newValue)
            }
            .onDisappear {
                focusTask?.cancel()
                pendingFocusValue = nil
            }
    }

    private func updateOverlayFocus(_ newValue: Bool) {
        focusTask?.cancel()

        guard newValue else {
            pendingFocusValue = nil
            isOverlayFocused = false
            return
        }

        pendingFocusValue = true
        focusTask = Task {
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }

            await MainActor.run {
                guard pendingFocusValue == true else { return }

                pendingFocusValue = nil
                isOverlayFocused = true
            }
        }
    }
}

struct PosterButton<Item: Poster, Overlay: View, Fallback: View>: View {
    let item: Item
    let posterType: PosterDisplayType
    let overlayOptions: PosterButtonOverlayOptions
    let unplayedIndicatorType: UnplayedIndicatorType

    private let imageSources: [ImageSource]?
    private let usesContextMenu: Bool
    private let usesDelayedOverlayFocus: Bool
    private let action: () -> Void
    private let fallback: () -> Fallback
    private let overlay: () -> Overlay

    init(
        item: Item,
        type: PosterDisplayType,
        overlayOptions: PosterButtonOverlayOptions = .default,
        unplayedIndicatorType: UnplayedIndicatorType = .none,
        imageSources: [ImageSource]? = nil,
        usesContextMenu: Bool = true,
        usesDelayedOverlayFocus: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder fallback: @escaping () -> Fallback,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.item = item
        self.posterType = type
        self.overlayOptions = overlayOptions
        self.unplayedIndicatorType = unplayedIndicatorType
        self.imageSources = imageSources
        self.usesContextMenu = usesContextMenu
        self.usesDelayedOverlayFocus = usesDelayedOverlayFocus
        self.action = action
        self.fallback = fallback
        self.overlay = overlay
    }

    private var button: some View {
        Button {
            action()
        } label: {
            PosterButtonContent(
                item: item,
                posterType: posterType,
                overlayOptions: overlayOptions,
                unplayedIndicatorType: unplayedIndicatorType,
                imageSources: imageSources,
                usesDelayedOverlayFocus: usesDelayedOverlayFocus,
                fallback: fallback,
                overlay: overlay
            )
        }
        .buttonStyle(.card)
        .accessibilityLabel(item.displayTitle)
    }

    var body: some View {
        if usesContextMenu {
            button
                .matchedContextMenu(for: item)
        } else {
            button
        }
    }
}

extension PosterButton where Fallback == PosterFallbackContentView {

    init(
        item: Item,
        type: PosterDisplayType,
        overlayOptions: PosterButtonOverlayOptions = .default,
        unplayedIndicatorType: UnplayedIndicatorType = .none,
        imageSources: [ImageSource]? = nil,
        usesContextMenu: Bool = true,
        usesDelayedOverlayFocus: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.init(
            item: item,
            type: type,
            overlayOptions: overlayOptions,
            unplayedIndicatorType: unplayedIndicatorType,
            imageSources: imageSources,
            usesContextMenu: usesContextMenu,
            usesDelayedOverlayFocus: usesDelayedOverlayFocus,
            action: action
        ) {
            PosterFallbackContentView(
                title: item.showTitle ? item.displayTitle : nil,
                systemName: item.systemImage
            )
        } overlay: {
            overlay()
        }
    }
}

extension PosterButton where Overlay == PosterButtonDefaultOverlay<Item> {

    init(
        item: Item,
        type: PosterDisplayType,
        overlayOptions: PosterButtonOverlayOptions = .default,
        unplayedIndicatorType: UnplayedIndicatorType = .none,
        imageSources: [ImageSource]? = nil,
        usesContextMenu: Bool = true,
        usesDelayedOverlayFocus: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.init(
            item: item,
            type: type,
            overlayOptions: overlayOptions,
            unplayedIndicatorType: unplayedIndicatorType,
            imageSources: imageSources,
            usesContextMenu: usesContextMenu,
            usesDelayedOverlayFocus: usesDelayedOverlayFocus,
            action: action,
            fallback: fallback
        ) {
            PosterButtonDefaultOverlay(
                item: item,
                overlayOptions: overlayOptions,
                unplayedIndicatorType: unplayedIndicatorType
            )
        }
    }
}

extension PosterButton where Overlay == PosterButtonDefaultOverlay<Item>, Fallback == PosterFallbackContentView {

    init(
        item: Item,
        type: PosterDisplayType,
        overlayOptions: PosterButtonOverlayOptions = .default,
        unplayedIndicatorType: UnplayedIndicatorType = .none,
        imageSources: [ImageSource]? = nil,
        usesContextMenu: Bool = true,
        usesDelayedOverlayFocus: Bool = true,
        action: @escaping () -> Void
    ) {
        self.init(
            item: item,
            type: type,
            overlayOptions: overlayOptions,
            unplayedIndicatorType: unplayedIndicatorType,
            imageSources: imageSources,
            usesContextMenu: usesContextMenu,
            usesDelayedOverlayFocus: usesDelayedOverlayFocus,
            action: action
        ) {
            PosterFallbackContentView(
                title: item.showTitle ? item.displayTitle : nil,
                systemName: item.systemImage
            )
        } overlay: {
            PosterButtonDefaultOverlay(
                item: item,
                overlayOptions: overlayOptions,
                unplayedIndicatorType: unplayedIndicatorType
            )
        }
    }
}

struct PosterButtonOverlayOptions: OptionSet {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let watched = Self(rawValue: 1 << 0)
    static let favorite = Self(rawValue: 1 << 1)
    static let progress = Self(rawValue: 1 << 2)
    static let unwatched = Self(rawValue: 1 << 3)
    static let seasonEpisodeLabel = Self(rawValue: 1 << 4)
    static let durationLeft = Self(rawValue: 1 << 5)

    static let `default`: Self = [
        .watched,
        .unwatched,
        .favorite,
        .progress,
        .seasonEpisodeLabel,
        .durationLeft,
    ]

    init(
        showPlayed: Bool,
        showFavorited: Bool,
        showProgress: Bool,
        showUnplayed: UnplayedIndicatorType
    ) {
        self = [.seasonEpisodeLabel, .durationLeft]

        if showPlayed {
            insert(.watched)
        }

        if showFavorited {
            insert(.favorite)
        }

        if showProgress {
            insert(.progress)
        }

        if showUnplayed != .none {
            insert(.unwatched)
        }
    }
}

struct PosterButtonContent<Item: Poster, Overlay: View, Fallback: View>: View {
    @Environment(\.isFocused)
    private var isFocused

    let item: Item
    let posterType: PosterDisplayType
    let overlayOptions: PosterButtonOverlayOptions
    let unplayedIndicatorType: UnplayedIndicatorType
    let imageSources: [ImageSource]?
    let usesDelayedOverlayFocus: Bool
    let fallback: () -> Fallback
    let overlay: () -> Overlay

    var body: some View {
        ZStack {
            PosterImage(
                item: item,
                type: posterType,
                imageSources: imageSources
            ) {
                fallback()
            }

            if usesDelayedOverlayFocus {
                overlay().posterOverlayFocus(isFocused)
            } else {
                overlay()
            }
        }
    }
}

struct PosterButtonDefaultOverlay<Item: Poster>: View {
    @Environment(\.isFocused)
    private var isFocused

    let item: Item
    let overlayOptions: PosterButtonOverlayOptions
    let unplayedIndicatorType: UnplayedIndicatorType
    var alwaysShowsBottomContent: Bool = false

    private var isBottomContentVisible: Bool {
        isFocused || alwaysShowsBottomContent
    }

    private var baseItem: BaseItemDto? {
        item as? BaseItemDto
    }

    private var isSeries: Bool {
        baseItem?.type == .series
    }

    private var isPlayed: Bool {
        baseItem?.userData?.isPlayed == true ||
            (baseItem?.userData?.playedPercentage ?? 0) >= 100
    }

    private var playbackProgress: Double {
        baseItem?.userData?.playedPercentage ?? 0.0
    }

    private var unplayedCount: Int {
        baseItem?.userData?.unplayedItemCount ?? 0
    }

    private var hasPlaybackProgress: Bool {
        (baseItem?.userData?.playbackPositionTicks ?? 0) > 0
    }

    private var seasonEpisodeLabel: String? {
        guard let baseItem else {
            return nil
        }

        if let seasonNumber = baseItem.parentIndexNumber,
           let episodeNumber = baseItem.indexNumber
        {
            return L10n.seasonAndEpisode(String(seasonNumber), String(episodeNumber))
        }

        return baseItem.seasonEpisodeLabel
    }

    private var durationLeftLabel: String? {
        if hasPlaybackProgress, !isPlayed, let progressLabel = baseItem?.progressLabel {
            return progressLabel
        }

        return baseItem?.runTimeLabel
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
            .opacity(isBottomContentVisible ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.18), value: isBottomContentVisible)
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
            .opacity(isBottomContentVisible ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.18), value: isBottomContentVisible)
    }

    @ViewBuilder
    private var unwatchedCountOverlay: some View {
        if unplayedIndicatorType == .count,
           unplayedCount > 0
        {
            Text(unplayedCount.description)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: 21)
                .frame(minWidth: 21)
                .background(.black.opacity(0.55), in: Capsule())
                .opacity(isBottomContentVisible ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.18), value: isBottomContentVisible)
        }
    }

    @ViewBuilder
    private var durationLeftOverlay: some View {
        if let durationLeftLabel {
            Text(durationLeftLabel)
                .font(.caption2)
                .foregroundStyle(.white)
                .opacity(isBottomContentVisible ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.18), value: isBottomContentVisible)
        }
    }

    @ViewBuilder
    private var metadataOverlay: some View {
        if baseItem?.type == .episode {
            DotHStack {
                if shouldShowSeasonEpisodeLabel, let seasonEpisodeLabel {
                    Text(seasonEpisodeLabel)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .opacity(isBottomContentVisible ? 1 : 0.4)
                        .animation(.easeInOut(duration: 0.18), value: isBottomContentVisible)
                }

                if shouldShowDurationLeft {
                    durationLeftOverlay
                }
            }.foregroundStyle(.white).opacity(isBottomContentVisible ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.18), value: isBottomContentVisible)
        }

        if baseItem?.type == .movie, shouldShowDurationLeft {
            durationLeftOverlay
        }
    }

    private var shouldShowWatchedOverlay: Bool {
        !isSeries &&
            isWatchedBranch &&
            overlayOptions.contains(.watched)
    }

    private var shouldShowFavorite: Bool {
        !isSeries &&
            overlayOptions.contains(.favorite) &&
            baseItem?.userData?.isFavorite == true
    }

    private var shouldShowProgressOverlay: Bool {
        !isSeries &&
            isProgressBranch &&
            overlayOptions.contains(.progress)
    }

    private var shouldShowUnwatchedOverlay: Bool {
        guard isUnwatchedBranch, overlayOptions.contains(.unwatched) else {
            return false
        }

        if isSeries {
            return unplayedIndicatorType == .count && unplayedCount > 0
        }

        return unplayedIndicatorType != .none
    }

    private var shouldShowSeasonEpisodeLabel: Bool {
        overlayOptions.contains(.seasonEpisodeLabel) &&
            seasonEpisodeLabel != nil
    }

    private var shouldShowDurationLeft: Bool {
        overlayOptions.contains(.durationLeft) &&
            durationLeftLabel != nil
    }

    private var shouldShowMetadataOverlay: Bool {
        guard !isSeries else { return false }

        return switch baseItem?.type {
        case .episode:
            shouldShowSeasonEpisodeLabel || shouldShowDurationLeft
        case .movie:
            shouldShowDurationLeft
        default:
            false
        }
    }

    private var shouldShowStatusOverlay: Bool {
        shouldShowWatchedOverlay ||
            shouldShowProgressOverlay ||
            shouldShowUnwatchedOverlay
    }

    private var shouldShowPlayOverlay: Bool {
        shouldShowWatchedOverlay ||
            shouldShowProgressOverlay ||
            (shouldShowUnwatchedOverlay && !isSeries)
    }

    private var shouldShowBottomOverlay: Bool {
        shouldShowStatusOverlay || shouldShowMetadataOverlay
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
        .opacity(isBottomContentVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: isBottomContentVisible)
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

    @ViewBuilder
    private var defaultOverlay: some View {
        if shouldShowFavorite {
            favoritedOverlay
        }

        if shouldShowBottomOverlay {
            bottomContent {
                if shouldShowPlayOverlay {
                    playOverlay
                }

                if shouldShowProgressOverlay {
                    progressOverlay
                } else if shouldShowUnwatchedOverlay {
                    unwatchedCountOverlay
                }

                metadataOverlay
            }
        }
    }

    var body: some View {
        defaultOverlay
    }
}
