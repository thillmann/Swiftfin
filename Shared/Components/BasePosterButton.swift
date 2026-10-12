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

enum PosterButtonLayout {
    static let landscapeExtensionHeight: CGFloat = 40
    static let landscapeExtensionOverlap: CGFloat = 16

    static var landscapeFooterHeight: CGFloat {
        landscapeExtensionHeight - landscapeExtensionOverlap
    }
}

struct LandscapePosterBackgroundFill<Item: PlatformPoster, Fallback: View>: View {

    let item: Item
    let imageSources: [ImageSource]?
    let height: CGFloat
    private let fallback: () -> Fallback

    init(
        item: Item,
        imageSources: [ImageSource]?,
        height: CGFloat,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.item = item
        self.imageSources = imageSources
        self.height = height
        self.fallback = fallback
    }

    var body: some View {
        PlatformPosterImage(
            item: item,
            type: .landscape,
            imageContentMode: .fill,
            appliesPosterStyle: false,
            imageSources: imageSources
        ) {
            fallback()
        }
        .frame(maxWidth: .infinity)
        .frame(height: PosterButtonLayout.landscapeExtensionHeight)
        .scaleEffect(
            x: 1.08,
            y: max(1, height / PosterButtonLayout.landscapeExtensionHeight) * 1.08,
            anchor: .bottom
        )
        .blur(radius: 8)
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .bottom)
        .clipped()
    }
}

struct LandscapePosterOverlayExtension<Item: PlatformPoster, Fallback: View>: View {

    let item: Item
    let imageSources: [ImageSource]?
    let height: CGFloat
    let fadeHeight: CGFloat
    let backgroundTintOpacity: CGFloat
    private let fallback: () -> Fallback

    init(
        item: Item,
        imageSources: [ImageSource]?,
        height: CGFloat,
        fadeHeight: CGFloat? = nil,
        backgroundTintOpacity: CGFloat = 0,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.item = item
        self.imageSources = imageSources
        self.height = height
        self.fadeHeight = fadeHeight ?? PosterButtonLayout.landscapeExtensionHeight
        self.backgroundTintOpacity = backgroundTintOpacity
        self.fallback = fallback
    }

    var body: some View {
        let fadeEndPoint = min(1, fadeHeight / height)

        LandscapePosterBackgroundFill(
            item: item,
            imageSources: imageSources,
            height: height,
            fallback: fallback
        )
        .overlay {
            Color.black.opacity(backgroundTintOpacity)
        }
        .mask {
            LinearGradient(
                colors: [.clear, .black.opacity(0.7), .black],
                startPoint: .top,
                endPoint: .init(x: 0.5, y: fadeEndPoint)
            )
        }
    }
}

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

struct BasePosterButton<Item: PlatformPoster, Overlay: View, Fallback: View>: View {

    let item: Item
    let posterType: PosterDisplayType
    let imageSources: [ImageSource]?
    let appliesPosterStyle: Bool
    private let fallback: () -> Fallback
    private let overlay: () -> Overlay

    init(
        item: Item,
        type: PosterDisplayType,
        imageSources: [ImageSource]?,
        appliesPosterStyle: Bool = true,
        @ViewBuilder fallback: @escaping () -> Fallback,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.item = item
        self.posterType = type
        self.imageSources = imageSources
        self.appliesPosterStyle = appliesPosterStyle
        self.fallback = fallback
        self.overlay = overlay
    }

    var body: some View {
        ZStack {
            PlatformPosterImage(
                item: item,
                type: posterType,
                appliesPosterStyle: appliesPosterStyle,
                imageSources: imageSources
            ) {
                fallback()
            }

            overlay()
        }
    }
}

struct PosterButtonTitleContentView: View {

    let title: String

    var body: some View {
        Text(title)
            .font(.footnote)
            .fontWeight(.regular)
            .foregroundStyle(.primary)
    }
}

struct PosterButtonSubtitleContentView: View {

    let subtitle: String?

    var body: some View {
        Text(subtitle ?? " ")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
    }
}

struct PosterButtonTitleSubtitleContentView<Item: PlatformPoster>: View {

    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.showTitle {
                PosterButtonTitleContentView(title: item.displayTitle)
                    .lineLimit(1, reservesSpace: true)
            }

            PosterButtonSubtitleContentView(subtitle: item.subtitle)
                .lineLimit(1, reservesSpace: true)
        }
    }
}

struct PosterButtonEpisodeContentSubtitleContent<Item: PlatformPoster>: View {

    @Default(.Customization.Episodes.useSeriesLandscapeBackdrop)
    private var useSeriesLandscapeBackdrop

    let item: Item

    var body: some View {
        if let item = item as? BaseItemDto {
            VStack(alignment: .leading, spacing: 0) {
                if item.showTitle, let seriesName = item.seriesName {
                    Text(seriesName)
                        .font(.footnote)
                        .fontWeight(.regular)
                        .foregroundColor(.primary)
                        .lineLimit(1, reservesSpace: true)
                }

                DotHStack(padding: 3) {
                    Text(item.seasonEpisodeLabel ?? .emptyDash)

                    if item.showTitle || useSeriesLandscapeBackdrop {
                        Text(item.displayTitle)
                    } else if let seriesName = item.seriesName {
                        Text(seriesName)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
        }
    }
}

struct PosterButtonDefaultOverlay<Item: PlatformPoster>: View {
    #if os(tvOS)
    @Environment(\.isFocused)
    private var isFocused
    #else
    @Default(.Customization.Indicators.showFavorited)
    private var showFavorited
    @Default(.Customization.Indicators.showProgress)
    private var showProgress
    @Default(.Customization.Indicators.showUnplayed)
    private var showUnplayed
    @Default(.Customization.Indicators.showPlayed)
    private var showPlayed
    #endif

    let item: Item
    let overlayOptions: PosterButtonOverlayOptions
    let unplayedIndicatorType: UnplayedIndicatorType
    var alwaysShowsBottomContent: Bool
    private let showsSeasonEpisodeLabel: Bool
    private let leadingBottomContent: AnyView?
    private let bottomContentHeight: CGFloat
    private let trailingOverlay: AnyView?

    init(
        item: Item,
        overlayOptions: PosterButtonOverlayOptions = .default,
        unplayedIndicatorType: UnplayedIndicatorType = .none,
        alwaysShowsBottomContent: Bool = false,
        showsSeasonEpisodeLabel: Bool = true,
        leadingBottomContent: AnyView? = nil,
        bottomContentHeight: CGFloat = 64,
        trailingOverlay: AnyView? = nil
    ) {
        self.item = item
        self.overlayOptions = overlayOptions
        self.unplayedIndicatorType = unplayedIndicatorType
        self.alwaysShowsBottomContent = alwaysShowsBottomContent
        self.showsSeasonEpisodeLabel = showsSeasonEpisodeLabel
        self.leadingBottomContent = leadingBottomContent
        self.bottomContentHeight = bottomContentHeight
        self.trailingOverlay = trailingOverlay
    }

    private var isBottomContentVisible: Bool {
        #if os(tvOS)
        isFocused || alwaysShowsBottomContent
        #else
        true
        #endif
    }

    private var isTopContentVisible: Bool {
        #if os(tvOS)
        isFocused
        #else
        true
        #endif
    }

    private var activeOverlayOptions: PosterButtonOverlayOptions {
        #if os(tvOS)
        overlayOptions
        #else
        PosterButtonOverlayOptions(
            showPlayed: showPlayed,
            showFavorited: showFavorited,
            showProgress: showProgress,
            showUnplayed: showUnplayed
        )
        #endif
    }

    private var activeUnplayedIndicatorType: UnplayedIndicatorType {
        #if os(tvOS)
        unplayedIndicatorType
        #else
        showUnplayed
        #endif
    }

    private var bottomOverlayFont: Font {
        #if os(iOS)
        .caption
        #else
        .caption2
        #endif
    }

    private var overlayForegroundColor: Color {
        #if os(iOS)
        .white.opacity(0.8)
        #else
        .white
        #endif
    }

    private var bottomContentInsets: EdgeInsets {
        #if os(iOS)
        .init(
            top: leadingBottomContent == nil ? 16 : 2,
            leading: 16,
            bottom: 10,
            trailing: 16
        )
        #else
        .init(16)
        #endif
    }

    private var bottomContentSpacing: CGFloat {
        #if os(iOS)
        8
        #else
        12
        #endif
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

    private var shouldShowSeasonEpisodeLabel: Bool {
        showsSeasonEpisodeLabel && activeOverlayOptions.contains(.seasonEpisodeLabel) && seasonEpisodeLabel != nil
    }

    private var shouldShowDurationLeft: Bool {
        activeOverlayOptions.contains(.durationLeft) && durationLeftLabel != nil
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
        canShowStatusIndicator && !isWatchedBranch && !isProgressBranch
    }

    @ViewBuilder
    private var playOverlay: some View {
        Image(systemName: isPlayed ? "arrow.counterclockwise" : "play.fill")
            .font(.caption2)
            .foregroundStyle(overlayForegroundColor)
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
                    .foregroundStyle(overlayForegroundColor)
                    .padding(7)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(12)
                    .opacity(isTopContentVisible ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.18), value: isTopContentVisible)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        ProgressView(value: playbackProgress / 100)
            .progressViewStyle(
                FeatureInlineProgressStyle(
                    trackColor: overlayForegroundColor.opacity(0.2),
                    fillColor: overlayForegroundColor
                )
            )
            .frame(width: 40)
            .opacity(isBottomContentVisible ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.18), value: isBottomContentVisible)
    }

    @ViewBuilder
    private var unwatchedCountOverlay: some View {
        if activeUnplayedIndicatorType == .count, unplayedCount > 0 {
            Text(unplayedCount.description)
                .font(bottomOverlayFont.weight(.semibold))
                .foregroundStyle(overlayForegroundColor)
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
                .font(bottomOverlayFont)
                .foregroundStyle(overlayForegroundColor)
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
                        .font(bottomOverlayFont)
                        .foregroundStyle(overlayForegroundColor)
                }

                if shouldShowDurationLeft {
                    durationLeftOverlay
                }
            }
            .foregroundStyle(overlayForegroundColor)
            .opacity(isBottomContentVisible ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.18), value: isBottomContentVisible)
        }

        if baseItem?.type == .movie, shouldShowDurationLeft {
            durationLeftOverlay
        }
    }

    private var shouldShowWatchedOverlay: Bool {
        !isSeries && isWatchedBranch && activeOverlayOptions.contains(.watched)
    }

    private var shouldShowFavorite: Bool {
        activeOverlayOptions.contains(.favorite) && baseItem?.userData?.isFavorite == true
    }

    private var shouldShowProgressOverlay: Bool {
        !isSeries && isProgressBranch && activeOverlayOptions.contains(.progress)
    }

    private var shouldShowUnwatchedOverlay: Bool {
        guard isUnwatchedBranch, activeOverlayOptions.contains(.unwatched) else {
            return false
        }

        if isSeries {
            return activeUnplayedIndicatorType == .count && unplayedCount > 0
        }

        return activeUnplayedIndicatorType != .none
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
        shouldShowWatchedOverlay || shouldShowProgressOverlay || shouldShowUnwatchedOverlay
    }

    private var shouldShowPlayOverlay: Bool {
        shouldShowWatchedOverlay ||
            shouldShowProgressOverlay ||
            (shouldShowUnwatchedOverlay && !isSeries)
    }

    private var shouldShowBottomOverlay: Bool {
        leadingBottomContent != nil || shouldShowStatusOverlay || shouldShowMetadataOverlay
    }

    @ViewBuilder
    private var bottomBackdrop: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.34), .black.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.85), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .opacity(isBottomContentVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: isBottomContentVisible)
    }

    @ViewBuilder
    private func bottomContent(@ViewBuilder content: () -> some View) -> some View {
        VStack {
            Spacer(minLength: 0)

            ZStack(alignment: .bottom) {
                bottomBackdrop
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    if let leadingBottomContent {
                        leadingBottomContent
                            .allowsHitTesting(false)
                    } else {
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .center, spacing: bottomContentSpacing) {
                        content()
                            .allowsHitTesting(false)

                        Spacer(minLength: 0)

                        trailingOverlay
                    }
                    .padding(bottomContentInsets)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: bottomContentHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var body: some View {
        if shouldShowFavorite {
            favoritedOverlay
                .allowsHitTesting(false)
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
}
