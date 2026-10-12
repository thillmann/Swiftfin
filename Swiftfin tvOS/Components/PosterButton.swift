//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension View {

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

struct PlatformPosterButton<Item: PlatformPoster, Overlay: View, Fallback: View>: View {

    @Environment(\.posterConfiguration)
    private var accessibilityConfiguration

    @Environment(\.isFocused)
    private var isFocused

    let item: Item
    let posterType: PosterDisplayType

    private let imageSources: [ImageSource]?
    private let usesContextMenu: Bool
    private let usesDelayedOverlayFocus: Bool
    private let action: () -> Void
    private let fallback: () -> Fallback
    private let overlay: () -> Overlay

    init(
        item: Item,
        type: PosterDisplayType,
        overlayOptions _: PosterButtonOverlayOptions = .default,
        unplayedIndicatorType _: UnplayedIndicatorType = .none,
        imageSources: [ImageSource]? = nil,
        usesContextMenu: Bool = true,
        usesDelayedOverlayFocus: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder fallback: @escaping () -> Fallback,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.item = item
        posterType = type
        self.imageSources = imageSources
        self.usesContextMenu = usesContextMenu
        self.usesDelayedOverlayFocus = usesDelayedOverlayFocus
        self.action = action
        self.fallback = fallback
        self.overlay = overlay
    }

    @ViewBuilder
    private var posterContent: some View {
        BasePosterButton(
            item: item,
            type: posterType,
            imageSources: imageSources,
            fallback: fallback
        ) {
            if usesDelayedOverlayFocus {
                overlay().posterOverlayFocus(isFocused)
            } else {
                overlay()
            }
        }
    }

    private var button: some View {
        Button {
            action()
        } label: {
            posterContent
        }
        .buttonStyle(.card)
        .accessibilityLabel(item.platformAccessibility(configuration: accessibilityConfiguration).label)
        .accessibilityValue(item.platformAccessibility(configuration: accessibilityConfiguration).value)
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
