//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension HomeView {

    struct CinematicResumeView: View {

        private enum ActionFocus: Hashable {
            case play
            case favorite
            case info
            case next
        }

        private struct PendingSelection {
            let index: Int
            let backgroundTransition: RotateContentView.Transition
        }

        private let heroBottomPadding: CGFloat = 310
        private let indicatorsBottomPadding: CGFloat = 170
        private let nextSectionRevealHeight: CGFloat = 230

        @Router
        private var router

        @ObservedObject
        var viewModel: HomeViewModel
        let presentation: HeroScrollPresentation

        @StateObject
        private var backgroundViewModel: CinematicBackgroundView.Proxy = .init(
            selectionDebounce: 0.05
        )
        @State
        private var selectedIndex = 0
        @State
        private var backgroundTransition: RotateContentView.Transition = .fade
        @State
        private var headerOpacity: Double = 1
        @State
        private var heroTransitionTask: Task<Void, Never>?
        @State
        private var pendingSelection: PendingSelection?
        @State
        private var detailedSelectedItem: BaseItemDto?
        @FocusState
        private var focusedAction: ActionFocus?

        private var items: [BaseItemDto] {
            viewModel.resumeItems.elements
        }

        private var selectedItem: BaseItemDto? {
            guard items.indices.contains(selectedIndex) else { return items.first }

            return items[selectedIndex]
        }

        private var indicatedIndex: Int {
            pendingSelection?.index ?? selectedIndex
        }

        private var heroItem: BaseItemDto? {
            guard let selectedItem else { return nil }

            if detailedSelectedItem?.id == selectedItem.id {
                return detailedSelectedItem
            }

            return selectedItem
        }

        private var iconFont: Font {
            .system(size: FeatureButtonTokens.baseHeight * 0.4, weight: .semibold)
        }

        private var contentOffset: CGFloat {
            presentation == .hero ? 0 : -nextSectionRevealHeight
        }

        var body: some View {
            ZStack(alignment: .topLeading) {
                CinematicBackgroundView(
                    viewModel: backgroundViewModel,
                    initialItem: items.first,
                    showsShadowGradient: false,
                    showsBlur: true
                )
                .frame(height: UIScreen.main.bounds.height)

                if let heroItem, let selectedItem {
                    heroContent(for: heroItem, actionItem: selectedItem)
                        .opacity(headerOpacity)
                        .padding(.leading, 80)
                        .padding(.trailing, 50)
                        .padding(.bottom, heroBottomPadding)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomLeading
                        )
                        .transition(.opacity)
                }

                pageIndicators
                    .padding(.horizontal, 80)
                    .padding(.bottom, indicatorsBottomPadding)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .bottom
                    )
            }
            .frame(height: UIScreen.main.bounds.height, alignment: .topLeading)
            .offset(y: contentOffset)
            .animation(.easeOut(duration: 0.6), value: contentOffset)
            .frame(maxWidth: .infinity)
            .frame(
                height: UIScreen.main.bounds.height - nextSectionRevealHeight,
                alignment: .top
            )
            .onAppear {
                selectCurrentItem()
            }
            .task(id: selectedItem?.id) {
                await refreshDetailedSelectedItem()
            }
            .onChange(of: selectedIndex) { _, _ in
                selectCurrentItem()
            }
            .onChange(of: items.map(\.id)) { _, _ in
                heroTransitionTask?.cancel()
                pendingSelection = nil
                headerOpacity = 1
                backgroundTransition = .fade
                selectedIndex = min(selectedIndex, max(items.count - 1, 0))
                selectCurrentItem()
            }
            .onDisappear {
                heroTransitionTask?.cancel()
                pendingSelection = nil
                headerOpacity = 1
            }
        }

        private func heroContent(for item: BaseItemDto, actionItem: BaseItemDto) -> some View {
            CinematicItemHeroView(item: item) { itemViewModel in
                ItemView.PlayButton(viewModel: itemViewModel, showsProgressBar: false)
                    .focused($focusedAction, equals: .play)
                    .onMoveCommand { direction in
                        if direction == .left {
                            focusedAction = .play
                            selectPreviousItem()
                        }
                    }

                favoriteButton(for: actionItem)
                    .focused($focusedAction, equals: .favorite)

                infoButton(for: actionItem)
                    .focused($focusedAction, equals: .info)

                if items.count > 1 {
                    Button {
                        focusedAction = .next
                        selectNextItem()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(iconFont)
                    }
                    .buttonStyle(.featureIconButton)
                    .focused($focusedAction, equals: .next)
                    .onMoveCommand { direction in
                        if direction == .right {
                            focusedAction = .next
                            selectNextItem()
                        }
                    }
                }
            }
            .focusSection()
            .defaultFocus(
                $focusedAction,
                .play,
                priority: .userInitiated
            )
        }

        private func favoriteButton(for item: BaseItemDto) -> some View {
            let isFavorite = item.userData?.isFavorite == true

            return Button {
                viewModel.send(.toggleIsFavorite(item))
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(iconFont)
            }
            .buttonStyle(.featureIconButton)
            .isSelected(isFavorite)
            .accessibilityLabel(L10n.favorited)
        }

        private func infoButton(for item: BaseItemDto) -> some View {
            Button {
                router.route(to: .item(item: item))
            } label: {
                Image(systemName: "info.circle")
                    .font(iconFont)
            }
            .buttonStyle(.featureIconButton)
            .accessibilityLabel(L10n.info)
        }

        private var pageIndicators: some View {
            HStack(spacing: 12) {
                ForEach(items.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index == indicatedIndex ? .white : .white.opacity(0.35))
                        .frame(width: index == indicatedIndex ? 36 : 10, height: 10)
                        .animation(
                            .spring(response: 0.34, dampingFraction: 0.82),
                            value: indicatedIndex
                        )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.2), value: indicatedIndex)
        }

        private func selectPreviousItem() {
            guard items.isNotEmpty else { return }

            transitionToItem(
                at: (indicatedIndex - 1 + items.count) % items.count,
                backgroundTransition: .parallaxFromLeading
            )
        }

        private func selectNextItem() {
            guard items.isNotEmpty else { return }

            transitionToItem(
                at: (indicatedIndex + 1) % items.count,
                backgroundTransition: .parallaxFromTrailing
            )
        }

        private func transitionToItem(
            at index: Int,
            backgroundTransition: RotateContentView.Transition
        ) {
            pendingSelection = PendingSelection(
                index: index,
                backgroundTransition: backgroundTransition
            )

            guard heroTransitionTask == nil else { return }

            heroTransitionTask = Task { @MainActor in
                withAnimation(.easeOut(duration: 0.18)) {
                    headerOpacity = 0
                }

                do {
                    // Keep the current hero in place until it is fully invisible.
                    try await Task.sleep(for: .milliseconds(180))

                    while !Task.isCancelled, let selection = pendingSelection {
                        pendingSelection = nil
                        self.backgroundTransition = selection.backgroundTransition
                        selectedIndex = selection.index

                        // Wait until shortly before the reveal settles. If another
                        // destination is pending, keep the hero hidden and reveal it next.
                        try await Task.sleep(for: .milliseconds(700))

                        if pendingSelection != nil {
                            try await Task.sleep(for: .milliseconds(100))
                            continue
                        }

                        withAnimation(.easeIn(duration: 0.2)) {
                            headerOpacity = 1
                        }

                        try await Task.sleep(for: .milliseconds(200))

                        guard pendingSelection != nil else { break }

                        withAnimation(.easeOut(duration: 0.18)) {
                            headerOpacity = 0
                        }

                        try await Task.sleep(for: .milliseconds(180))
                    }
                } catch is CancellationError {
                    // Cancellation is expected when this view disappears or reloads.
                } catch {
                    // Timing sleeps have no other expected failure mode.
                }

                heroTransitionTask = nil
            }
        }

        private func selectCurrentItem() {
            guard let selectedItem else { return }

            backgroundViewModel.select(
                item: selectedItem,
                transition: backgroundTransition
            )
        }

        private func refreshDetailedSelectedItem() async {
            guard let selectedItem else {
                detailedSelectedItem = nil
                return
            }

            guard let userSession = viewModel.userSession else {
                detailedSelectedItem = nil
                return
            }

            detailedSelectedItem = nil

            do {
                let fullItem = try await selectedItem.getFullItem(userSession: userSession)

                guard !Task.isCancelled, fullItem.id == selectedItem.id else { return }

                detailedSelectedItem = fullItem
            } catch {
                // Keep the lightweight resume item if the full metadata request fails.
            }
        }
    }
}
