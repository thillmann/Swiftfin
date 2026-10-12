//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Get
import JellyfinAPI
import SwiftUI

extension EnvironmentValues {

    @Entry
    var fixedPosterButtonSize: CGSize? = nil
}

struct PlatformPosterButton<Item: PlatformPoster, Overlay: View, Fallback: View>: View {

    @Environment(\.posterConfiguration)
    private var accessibilityConfiguration

    @EnvironmentTypeValue<Item>(\.posterOverlayRegistry)
    private var posterOverlayRegistry

    @Environment(\.contextMenuRegistry)
    private var contextMenuRegistry

    @Environment(\.fixedPosterButtonSize)
    private var fixedPosterButtonSize

    @Namespace
    private var namespace

    @State
    private var posterVisualSize: CGSize = .zero

    @Default(.Customization.showPosterLabels)
    private var showPosterLabels

    let item: Item
    let posterType: PosterDisplayType

    private let imageSources: [ImageSource]?
    private let usesContextMenu: Bool
    private let action: () -> Void
    private let transitionAction: ((Namespace.ID) -> Void)?
    private let menuItem: BaseItemDto?
    private let fallback: () -> Fallback
    private let overlay: () -> Overlay
    private let label: (any View)?

    private init(
        item: Item,
        type: PosterDisplayType,
        imageSources: [ImageSource]?,
        usesContextMenu: Bool,
        action: @escaping () -> Void,
        transitionAction: ((Namespace.ID) -> Void)? = nil,
        menuItem: BaseItemDto? = nil,
        @ViewBuilder fallback: @escaping () -> Fallback,
        @ViewBuilder overlay: @escaping () -> Overlay,
        label: (any View)?
    ) {
        self.item = item
        posterType = type
        self.imageSources = imageSources
        self.usesContextMenu = usesContextMenu
        self.action = action
        self.transitionAction = transitionAction
        self.menuItem = menuItem
        self.fallback = fallback
        self.overlay = overlay
        self.label = label
    }

    init(
        item: Item,
        type: PosterDisplayType,
        overlayOptions: PosterButtonOverlayOptions = .default,
        unplayedIndicatorType: UnplayedIndicatorType = .none,
        imageSources: [ImageSource]? = nil,
        usesContextMenu: Bool = true,
        usesDelayedOverlayFocus _: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder fallback: @escaping () -> Fallback,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.init(
            item: item,
            type: type,
            imageSources: imageSources,
            usesContextMenu: usesContextMenu,
            action: action,
            fallback: fallback,
            overlay: overlay,
            label: nil
        )
    }

    @ViewBuilder
    private func posterContent(overlay: some View) -> some View {
        primaryButton
            .overlay { overlay }
    }

    private var primaryButtonContent: some View {
        Button {
            if let transitionAction {
                transitionAction(namespace)
            } else {
                action()
            }
        } label: {
            VStack(spacing: posterType == .landscape ? -PosterButtonLayout.landscapeExtensionOverlap : 0) {
                BasePosterButton(
                    item: item,
                    type: posterType,
                    imageSources: imageSources,
                    appliesPosterStyle: posterType != .landscape,
                    fallback: fallback
                ) {
                    EmptyView()
                }

                landscapeOverlayExtension
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.primary, .secondary)
        .accessibilityLabel(item.platformAccessibility(configuration: accessibilityConfiguration).label)
        .accessibilityValue(item.platformAccessibility(configuration: accessibilityConfiguration).value)
    }

    /// Adds a shallow, feathered continuation below landscape artwork for its metadata.
    @ViewBuilder
    private var landscapeOverlayExtension: some View {
        if posterType == .landscape {
            LandscapePosterOverlayExtension(
                item: item,
                imageSources: imageSources,
                height: PosterButtonLayout.landscapeExtensionHeight
            ) {
                fallback()
            }
            .zIndex(1)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if #available(iOS 26.0, *) {
            primaryButtonContent
                .buttonStyle(.plain)
        } else {
            primaryButtonContent
                .buttonStyle(.card)
        }
    }

    @ViewBuilder
    private func iOSPosterView(overlay: some View) -> some View {
        VStack(alignment: .leading) {
            sizedPosterVisual(overlay: overlay)
                .backport
                .matchedTransitionSource(id: "item", in: namespace)
                .posterShadow()
                .trackingSize($posterVisualSize)

            if showPosterLabels, let label {
                label
                    .eraseToAnyView()
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func sizedPosterVisual(overlay: some View) -> some View {
        if let fixedPosterButtonSize {
            posterVisual(overlay: overlay)
                .frame(
                    width: fixedPosterButtonSize.width,
                    height: fixedPosterButtonSize.height
                )
        } else {
            posterVisual(overlay: overlay)
        }
    }

    @ViewBuilder
    private func posterVisual(
        overlay: some View,
        usesContextMenuPreviewShape: Bool = true
    ) -> some View {
        let content = posterContent(overlay: overlay)
            .posterGlassStyle(posterType)

        if usesContextMenuPreviewShape {
            content.contentShape(.contextMenuPreview, Rectangle())
        } else {
            content
        }
    }

    @ViewBuilder
    private var poster: some View {
        if posterType == .portrait {
            iOSPosterView(overlay: EmptyView())
        } else {
            let overlay = posterOverlayRegistry?(item) ?? overlay().eraseToAnyView()
            iOSPosterView(overlay: overlay)
        }
    }

    private var registeredContextMenu: (items: AnyView, preview: AnyView?)? {
        contextMenuRegistry.getvalue(for: Item.self)?(item)
    }

    private var shouldShowPosterMenu: Bool {
        guard let menuItem else { return false }
        return PosterButtonMenuActions.supports(menuItem)
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if let registeredContextMenu {
            registeredContextMenu.items
        }

        if let menuItem, shouldShowPosterMenu {
            PosterButtonMenuActions(item: menuItem)
        }
    }

    var body: some View {
        if usesContextMenu, registeredContextMenu != nil || shouldShowPosterMenu {
            poster
                .contextMenu {
                    contextMenuContent
                } preview: {
                    let frameScale = UIDevice.isPad && posterType == .landscape ? 1.0 : 1.3
                    let previewShape = RoundedRectangle(cornerRadius: 14, style: .continuous)

                    let previewContent = VStack(alignment: .leading, spacing: 12) {
                        posterVisual(
                            overlay: EmptyView(),
                            usesContextMenuPreviewShape: !UIDevice.isPad
                        )
                        .frame(
                            width: posterVisualSize.width * frameScale,
                            height: posterVisualSize.height * frameScale
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            if let baseItem = item as? BaseItemDto,
                               baseItem.type == .episode,
                               let seasonEpisodeLabel = baseItem.seasonEpisodeLabel
                            {
                                Text(seasonEpisodeLabel)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Text(item.displayTitle)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)

                    if UIDevice.isPad {
                        previewContent
                            .background(Color(uiColor: UIColor.secondarySystemGroupedBackground), in: previewShape)
                            .clipShape(previewShape)
                            .contentShape(.contextMenuPreview, previewShape)
                    } else {
                        previewContent
                            .background {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(uiColor: UIColor.secondarySystemGroupedBackground))
                            }
                    }
                }
        } else {
            poster
        }
    }
}

private func posterButtonTrailingOverlay(for item: some PlatformPoster) -> AnyView? {
    guard let item = item as? BaseItemDto,
          PosterButtonMenuActions.supports(item)
    else {
        return nil
    }

    return AnyView(PosterButtonOverlayMenu(item: item))
}

extension PlatformPosterButton where Fallback == PosterFallbackContentView {

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

extension PlatformPosterButton where Overlay == PosterButtonDefaultOverlay<Item> {

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
            imageSources: imageSources,
            usesContextMenu: usesContextMenu,
            action: action,
            menuItem: item as? BaseItemDto,
            fallback: fallback,
            overlay: {
                PosterButtonDefaultOverlay(
                    item: item,
                    overlayOptions: overlayOptions,
                    unplayedIndicatorType: unplayedIndicatorType,
                    trailingOverlay: posterButtonTrailingOverlay(for: item)
                )
            },
            label: nil
        )
    }
}

extension PlatformPosterButton where Overlay == PosterButtonDefaultOverlay<Item>, Fallback == PosterFallbackContentView {

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
            imageSources: imageSources,
            usesContextMenu: usesContextMenu,
            action: action,
            menuItem: item as? BaseItemDto,
            fallback: {
                PosterFallbackContentView(
                    title: item.showTitle ? item.displayTitle : nil,
                    systemName: item.systemImage
                )
            },
            overlay: {
                PosterButtonDefaultOverlay(
                    item: item,
                    overlayOptions: overlayOptions,
                    unplayedIndicatorType: unplayedIndicatorType,
                    trailingOverlay: posterButtonTrailingOverlay(for: item)
                )
            },
            label: nil
        )
    }

    init(
        item: Item,
        type: PosterDisplayType,
        action: @escaping (Namespace.ID) -> Void,
        @ViewBuilder label: @escaping () -> some View
    ) {
        self.init(
            item: item,
            type: type,
            imageSources: nil,
            usesContextMenu: true,
            action: {},
            transitionAction: action,
            menuItem: item as? BaseItemDto,
            fallback: {
                PosterFallbackContentView(
                    title: item.showTitle ? item.displayTitle : nil,
                    systemName: item.systemImage
                )
            },
            overlay: {
                PosterButtonDefaultOverlay(
                    item: item,
                    overlayOptions: .default,
                    unplayedIndicatorType: .none,
                    trailingOverlay: posterButtonTrailingOverlay(for: item)
                )
            },
            label: label()
        )
    }
}

struct PosterButtonOverlayMenu: View {

    @ObservedObject
    private var downloadManager = Container.shared.downloadManager()

    let item: BaseItemDto
    private let showsSeriesDestination: Bool

    init(item: BaseItemDto, showsSeriesDestination: Bool = true) {
        self.item = item
        self.showsSeriesDestination = showsSeriesDestination
    }

    var body: some View {
        Menu {
            PosterButtonMenuActions(item: item, showsSeriesDestination: showsSeriesDestination)
        } label: {
            HStack(spacing: 6) {
                if let downloadTask = downloadManager.task(for: item) {
                    PosterDownloadedIndicator(downloadTask: downloadTask)
                }

                Image(systemName: "ellipsis")
                    .font(.callout.weight(.bold))
                    .frame(width: 24, height: 24)
            }
            .frame(height: 24)
            .frame(minWidth: 24, alignment: .trailing)
            .contentShape(Rectangle().inset(by: -10))
        }
        .tint(.white.opacity(0.8))
        .accessibilityLabel(L10n.options)
    }
}

private struct PosterDownloadedIndicator: View {

    @ObservedObject
    var downloadTask: DownloadTask

    var body: some View {
        if case .complete = downloadTask.state {
            Image(systemName: "arrow.down.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        }
    }
}

struct PosterButtonMenuActions: View {

    @Router
    private var router

    @State
    private var isFavorite: Bool

    @State
    private var isPlayed: Bool

    let item: BaseItemDto
    private let showsSeriesDestination: Bool

    init(item: BaseItemDto, showsSeriesDestination: Bool = true) {
        self.item = item
        self.showsSeriesDestination = showsSeriesDestination
        _isFavorite = State(initialValue: item.userData?.isFavorite == true)
        _isPlayed = State(initialValue: item.userData?.isPlayed == true)
    }

    static func supports(_ item: BaseItemDto) -> Bool {
        switch item.type {
        case .episode, .movie, .series:
            true
        default:
            false
        }
    }

    private var destinationTitle: String {
        switch item.type {
        case .episode:
            "Go to Episode"
        case .movie:
            "Go to Movie"
        default:
            L10n.goToShow
        }
    }

    private var favoriteTitle: String {
        isFavorite
            ? "Remove from Favorites"
            : "Add to Favorites"
    }

    private var watchedTitle: String {
        isPlayed
            ? "Mark as Unwatched"
            : "Mark as Watched"
    }

    var body: some View {
        Button {
            router.route(to: .item(item: item))
        } label: {
            Label(destinationTitle, systemImage: "info.circle")
        }

        if showsSeriesDestination, item.type == .episode, let seriesID = item.seriesID {
            Button {
                router.route(
                    to: .item(
                        item: .init(
                            id: seriesID,
                            name: item.seriesName,
                            type: .series
                        )
                    )
                )
            } label: {
                Label(L10n.goToShow, systemImage: "info.circle")
            }
        }

        Button {
            toggleFavorite()
        } label: {
            Label(favoriteTitle, systemImage: isFavorite ? "heart.slash" : "heart")
        }

        if item.canBePlayed {
            Button {
                toggleWatched()
            } label: {
                Label(watchedTitle, systemImage: isPlayed ? "eye.slash" : "checkmark.circle")
            }
        }
    }

    private func toggleFavorite() {
        guard item.id != nil, Container.shared.currentUserSession() != nil else { return }

        let newValue = !isFavorite
        isFavorite = newValue

        Task { @MainActor in
            do {
                try await setFavorite(newValue)
                postUserDataUpdate(isFavorite: newValue)
            } catch {
                isFavorite.toggle()
            }
        }
    }

    private func toggleWatched() {
        guard item.id != nil, Container.shared.currentUserSession() != nil else { return }

        let newValue = !isPlayed
        isPlayed = newValue

        Task { @MainActor in
            do {
                try await setPlayed(newValue)
                postUserDataUpdate(isPlayed: newValue)
            } catch {
                isPlayed.toggle()
            }
        }
    }

    private func setFavorite(_ isFavorite: Bool) async throws {
        guard let session = Container.shared.currentUserSession() else { throw UserSessionError.missingCurrentSession }
        let entry = ItemEntry(item: try session.items.record(for: item))
        try await session.setFavorite(entry, to: isFavorite)
    }

    private func setPlayed(_ isPlayed: Bool) async throws {
        guard let session = Container.shared.currentUserSession() else { throw UserSessionError.missingCurrentSession }
        let entry = ItemEntry(item: try session.items.record(for: item))
        try await session.setPlayed(entry, to: isPlayed)
    }

    private func postUserDataUpdate(isFavorite: Bool? = nil, isPlayed: Bool? = nil) {
        guard item.id != nil else { return }

        var updatedItem = item
        var userData = updatedItem.userData ?? .init()

        if let isFavorite {
            userData.isFavorite = isFavorite
        }

        if let isPlayed {
            userData.isPlayed = isPlayed
        }

        updatedItem.userData = userData
        Notifications[.itemMetadataDidChange].post(updatedItem)
    }
}
