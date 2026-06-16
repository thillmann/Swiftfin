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

        @Router
        private var router

        @ObservedObject
        var viewModel: HomeViewModel

        @StateObject
        private var backgroundViewModel: CinematicBackgroundView.Proxy = .init()
        @State
        private var selectedIndex = 0
        @State
        private var backgroundTransition: RotateContentView.Transition = .fade
        @State
        private var headerOpacity: Double = 1
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

        var body: some View {
            ZStack(alignment: .bottomLeading) {
                CinematicBackgroundView(
                    viewModel: backgroundViewModel,
                    initialItem: items.first
                )
                .frame(height: UIScreen.main.bounds.height)
                .maskLinearGradient {
                    (location: 0.9, opacity: 1)
                    (location: 1, opacity: 0)
                }

                if let heroItem {
                    VStack(spacing: 48) {
                        heroContent(for: heroItem)
                            .opacity(headerOpacity)

                        pageIndicators
                    }
                    .padding(.leading, 80)
                    .padding(.trailing, 50)
                    .padding(.bottom, 110)
                    .transition(.opacity)
                }
            }
            .frame(height: UIScreen.main.bounds.height - 75, alignment: .bottomLeading)
            .frame(maxWidth: .infinity)
            .onAppear {
                selectCurrentItem()
            }
            .task(id: selectedItem?.id) {
                await refreshDetailedSelectedItem()
            }
            .onChange(of: selectedIndex) { _, _ in
                fadeHeaderIn()
                selectCurrentItem()
            }
            .onChange(of: items.map(\.id)) { _, _ in
                backgroundTransition = .fade
                selectedIndex = min(selectedIndex, max(items.count - 1, 0))
                selectCurrentItem()
            }
        }

        private func heroContent(for item: BaseItemDto) -> some View {
            CinematicItemHeroView(item: item) { itemViewModel in
                ItemView.PlayButton(viewModel: itemViewModel, showsProgressBar: false)
                    .focused($focusedAction, equals: .play)
                    .onMoveCommand { direction in
                        if direction == .left {
                            focusedAction = .play
                            selectPreviousItem()
                        }
                    }

                favoriteButton(for: item)
                    .focused($focusedAction, equals: .favorite)

                infoButton(for: item)
                    .focused($focusedAction, equals: .info)

                nextButton
                    .focused($focusedAction, equals: .next)
                    .onMoveCommand { direction in
                        if direction == .right {
                            focusedAction = .next
                            selectNextItem()
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
                router.route(to: .item(item: detailItem(for: item)))
            } label: {
                Image(systemName: "info.circle")
                    .font(iconFont)
            }
            .buttonStyle(.featureIconButton)
            .accessibilityLabel(L10n.info)
        }

        private var nextButton: some View {
            Button {
                focusedAction = .next
                selectNextItem()
            } label: {
                Image(systemName: "chevron.right")
                    .font(iconFont)
            }
            .buttonStyle(.featureIconButton)
            .accessibilityLabel(L10n.next)
            .enabled(items.count > 1)
        }

        private var pageIndicators: some View {
            HStack(spacing: 12) {
                ForEach(items.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index == selectedIndex ? .white : .white.opacity(0.35))
                        .frame(width: index == selectedIndex ? 36 : 10, height: 10)
                        .animation(
                            .spring(response: 0.34, dampingFraction: 0.82),
                            value: selectedIndex
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.2), value: selectedIndex)
        }

        private func detailItem(for item: BaseItemDto) -> BaseItemDto {
            guard item.type == .episode, let seriesID = item.seriesID else { return item }

            return BaseItemDto(
                id: seriesID,
                name: item.seriesName,
                type: .series
            )
        }

        private func selectPreviousItem() {
            guard items.isNotEmpty else { return }

            backgroundTransition = .slideFromLeading
            selectedIndex = (selectedIndex - 1 + items.count) % items.count
        }

        private func selectNextItem() {
            guard items.isNotEmpty else { return }

            backgroundTransition = .slideFromTrailing
            selectedIndex = (selectedIndex + 1) % items.count
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

            detailedSelectedItem = nil

            do {
                let fullItem = try await selectedItem.getFullItem(userSession: viewModel.userSession)

                guard !Task.isCancelled, fullItem.id == selectedItem.id else { return }

                detailedSelectedItem = fullItem
            } catch {
                // Keep the lightweight resume item if the full metadata request fails.
            }
        }

        private func fadeHeaderIn() {
            var transaction = Transaction()
            transaction.disablesAnimations = true

            withTransaction(transaction) {
                headerOpacity = 0.2
            }

            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.28)) {
                    headerOpacity = 1
                }
            }
        }
    }
}
