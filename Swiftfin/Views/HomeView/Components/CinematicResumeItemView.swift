//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI
import SwiftUI

final class HeroCarouselState: ObservableObject {

    @Published
    var selectedIndex = 0
    @Published
    var carouselDragOffset: CGFloat = 0
    @Published
    var isDraggingCarousel = false
    @Published
    var isSettlingCarousel = false
    @Published
    var pendingSelectionIndex: Int?
}

final class HeroBackdropScrollState: ObservableObject {

    @Published
    var offset: CGFloat = 0
}

extension HomeView {

    struct CinematicResumeBackdrop: View {

        let items: [BaseItemDto]
        @ObservedObject
        var carouselState: HeroCarouselState
        @ObservedObject
        var scrollState: HeroBackdropScrollState
        let viewportSize: CGSize

        var body: some View {
            ZStack {
                Color.systemBackground

                ForEach(visibleBackgroundIndices, id: \.self) { index in
                    HeroBackdropPage(
                        item: items[index],
                        viewportSize: viewportSize,
                        horizontalBleed: pageBleed
                    )
                    .offset(
                        x: backgroundOffset(for: index),
                        y: verticalParallaxOffset
                    )
                    .zIndex(index == carouselState.selectedIndex ? 1 : 0)
                    .accessibilityHidden(index != carouselState.selectedIndex)
                }
            }
            .frame(width: viewportSize.width, height: viewportSize.height)
            .clipped()
            .scaleEffect(pullDownScale, anchor: .top)
        }

        private var visibleBackgroundIndices: [Int] {
            guard items.indices.contains(carouselState.selectedIndex) else { return [] }

            var indices = [carouselState.selectedIndex]

            // Keep both neighbours alive just outside the viewport. Besides
            // making either direction immediately available, this gives the
            // crop and image pipeline time to finish before the page enters.
            for offset in [-1, 1] {
                if let index = wrappedIndex(carouselState.selectedIndex + offset), !indices.contains(index) {
                    indices.append(index)
                }
            }

            return indices
        }

        private var verticalParallaxOffset: CGFloat {
            -min(max(scrollState.offset, 0) * verticalParallaxFactor, viewportSize.height)
        }

        private var pullDownScale: CGFloat {
            guard scrollState.offset < 0, viewportSize.height > 0 else { return 1 }

            return (viewportSize.height - scrollState.offset) / viewportSize.height
        }

        private func backgroundOffset(for index: Int) -> CGFloat {
            let width = viewportSize.width

            if index == carouselState.selectedIndex {
                return carouselState.carouselDragOffset
            }

            if items.count == 2, carouselState.carouselDragOffset > 0 {
                return -width + carouselState.carouselDragOffset
            }

            if let nextIndex = wrappedIndex(carouselState.selectedIndex + 1), index == nextIndex {
                return width + min(carouselState.carouselDragOffset, 0)
            }

            return -width + max(carouselState.carouselDragOffset, 0)
        }

        private func wrappedIndex(_ index: Int) -> Int? {
            guard items.isNotEmpty else { return nil }

            return (index % items.count + items.count) % items.count
        }

        private let verticalParallaxFactor: CGFloat = 0.24
        private let pageBleed: CGFloat = 1
    }

    private struct HeroBackdropPage: View {

        let item: BaseItemDto
        let viewportSize: CGSize
        let horizontalBleed: CGFloat

        private var pageSize: CGSize {
            CGSize(
                width: viewportSize.width + horizontalBleed * 2,
                height: viewportSize.height
            )
        }

        var body: some View {
            let bottomColor = item.blurHash(for: .backdrop)?.averageLinearColor ?? Color.secondarySystemFill

            // This frame and target aspect ratio remain constant as the
            // foreground scrolls, so scrolling never recrops or zooms it.
            CinematicBackdropView(
                source: backgroundSource,
                bottomColor: bottomColor,
                size: pageSize,
                targetAspectRatio: viewportSize.width / viewportSize.height,
                alignment: .top
            )
        }

        private var backgroundSource: ImageSource {
            // The tall iPhone hero crops a wide backdrop substantially. Request
            // enough source width for the cropped image to fill its full height.
            let maxWidth = max(1200, pageSize.height * 1.77)

            if item.type == .episode {
                return episodeSeriesBackdropSource(maxWidth: maxWidth)
            }

            return item.imageSource(.backdrop, maxWidth: maxWidth)
        }

        private func episodeSeriesBackdropSource(maxWidth: CGFloat) -> ImageSource {
            guard let seriesItemID = item.seriesID ?? item.parentBackdropItemID else {
                return item.imageSource(.backdrop, maxWidth: maxWidth)
            }

            var seriesItem = item
            seriesItem.id = seriesItemID
            seriesItem.backdropImageTags = item.parentBackdropItemID == seriesItemID
                ? item.parentBackdropImageTags
                : nil

            let url = seriesItem._imageURL(
                .backdrop,
                maxWidth: maxWidth,
                maxHeight: nil,
                quality: nil,
                itemID: seriesItemID,
                requireTag: false
            )

            return ImageSource(
                url: url,
                blurHash: item.blurHashString(for: .backdrop)
            )
        }
    }
}

extension HomeView {

    /// The iOS counterpart to the tvOS resume hero.
    struct CinematicResumeItemView: View {

        @Router
        private var router

        @ObservedObject
        var viewModel: HomeViewModel
        @ObservedObject
        var carouselState: HeroCarouselState

        let height: CGFloat

        @StateObject
        private var selectedItemViewModel: ItemViewModel
        @State
        private var detailsRevealOpacity: CGFloat = 1

        init(viewModel: HomeViewModel, carouselState: HeroCarouselState, height: CGFloat) {
            self.viewModel = viewModel
            self._carouselState = ObservedObject(wrappedValue: carouselState)
            self.height = height
            self._selectedItemViewModel = StateObject(
                wrappedValue: ItemViewModel(item: viewModel.resumeItems.elements.first ?? BaseItemDto(id: ""))
            )
        }

        private var items: [BaseItemDto] {
            viewModel.resumeItems.elements
        }

        private var selectedItem: BaseItemDto? {
            guard items.indices.contains(carouselState.selectedIndex) else { return items.first }

            return items[carouselState.selectedIndex]
        }

        private var indicatedIndex: Int {
            carouselState.pendingSelectionIndex ?? carouselState.selectedIndex
        }

        var body: some View {
            GeometryReader { proxy in
                heroContent(width: proxy.size.width)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    selectItem(at: carouselState.selectedIndex + 1)
                case .decrement:
                    selectItem(at: carouselState.selectedIndex - 1)
                @unknown default:
                    break
                }
            }
            .onChange(of: items.map(\.id)) { _, _ in
                carouselState.selectedIndex = min(carouselState.selectedIndex, max(items.count - 1, 0))
                resetCarouselDrag()
                updateSelectedItemViewModel()
            }
            .task(id: selectedItem?.id) {
                updateSelectedItemViewModel()
            }
        }

        @ViewBuilder
        private func heroContent(width: CGFloat) -> some View {
            ZStack(alignment: .bottom) {
                carouselGestureView(width: width)

                CinematicHeroBlurOverlay()

                if let selectedItem {
                    HeroDetails(
                        item: selectedItem,
                        viewModel: viewModel,
                        actionViewModel: selectedItemViewModel
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 76)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: UIDevice.isPad ? .bottomLeading : .bottom
                    )
                    .id(carouselState.selectedIndex)
                    .opacity(detailsOpacity(for: width) * detailsRevealOpacity)
                    .offset(x: carouselState.carouselDragOffset * 0.12)
                }

                pageIndicators
                    .padding(.bottom, 24)
            }
            .frame(width: width, height: height)
        }

        private func detailsOpacity(for width: CGFloat) -> CGFloat {
            guard width > 0 else { return 1 }

            return max(0, 1 - abs(carouselState.carouselDragOffset / width) * 1.7)
        }

        private var pageIndicators: some View {
            HStack(spacing: 8) {
                ForEach(items.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index == indicatedIndex ? .white : .white.opacity(0.35))
                        .frame(width: index == indicatedIndex ? 28 : 8, height: 8)
                        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: indicatedIndex)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.45), in: Capsule(style: .continuous))
            .animation(.easeOut(duration: 0.2), value: indicatedIndex)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(indicatedIndex + 1) of \(items.count)")
        }

        private func updateSelectedItemViewModel() {
            guard let selectedItem else { return }

            selectedItemViewModel.send(.replace(selectedItem))
        }

        private func carouselGestureView(width: CGFloat) -> some View {
            GestureView()
                .environment(\.panGestureDirection, .horizontal)
                .environment(
                    \.tapGestureAction,
                    .init(action: { _, _, count in
                        guard count == 1, let selectedItem else { return }

                        router.route(to: .item(item: selectedItem))
                    })
                )
                .environment(
                    \.panAction,
                    .init(action: { translation, velocity, _, _, state in
                        switch state {
                        case .changed:
                            updateCarouselDrag(translation: translation, width: width)

                        case .ended, .cancelled, .failed:
                            finishCarouselDrag(
                                translation: translation,
                                velocity: velocity,
                                width: width
                            )

                        default:
                            break
                        }
                    })
                )
                .frame(width: width, height: height)
        }

        private func updateCarouselDrag(translation: CGPoint, width: CGFloat) {
            guard !carouselState.isSettlingCarousel else { return }

            carouselState.isDraggingCarousel = true
            carouselState.carouselDragOffset = constrainedDragOffset(translation.x, width: width)
        }

        private func finishCarouselDrag(translation: CGPoint, velocity: CGPoint, width: CGFloat) {
            defer { carouselState.isDraggingCarousel = false }

            guard carouselState.isDraggingCarousel else { return }

            let dragOffset = constrainedDragOffset(translation.x, width: width)
            let projectedOffset = velocity.x * 0.16
            let swipeDistance = abs(dragOffset) > width * 0.18 ? dragOffset : projectedOffset

            guard items.count > 1,
                  abs(swipeDistance) > width * 0.18,
                  let targetIndex = wrappedIndex(carouselState.selectedIndex + (swipeDistance < 0 ? 1 : -1))
            else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    carouselState.carouselDragOffset = 0
                }
                return
            }

            carouselState.isSettlingCarousel = true
            withAnimation(.easeOut(duration: Self.carouselSettleDuration)) {
                carouselState.pendingSelectionIndex = targetIndex
                carouselState.carouselDragOffset = swipeDistance < 0 ? -width : width
                detailsRevealOpacity = 0
            }

            finishCarouselTransition(at: targetIndex)
        }

        private func constrainedDragOffset(_ offset: CGFloat, width: CGFloat) -> CGFloat {
            guard items.count > 1 else { return offset * 0.18 }

            return min(max(offset, -width), width)
        }

        private func finishCarouselTransition(at index: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.carouselSettleDuration) {
                guard self.carouselState.isSettlingCarousel,
                      self.carouselState.pendingSelectionIndex == index
                else { return }

                var transaction = Transaction()
                transaction.disablesAnimations = true

                withTransaction(transaction) {
                    self.carouselState.selectedIndex = index
                    self.carouselState.pendingSelectionIndex = nil
                    self.carouselState.carouselDragOffset = 0
                    self.carouselState.isSettlingCarousel = false
                }

                withAnimation(.easeIn(duration: Self.detailsRevealDuration)) {
                    self.detailsRevealOpacity = 1
                }
            }
        }

        private func resetCarouselDrag() {
            carouselState.carouselDragOffset = 0
            carouselState.isDraggingCarousel = false
            carouselState.isSettlingCarousel = false
            carouselState.pendingSelectionIndex = nil
            detailsRevealOpacity = 1
        }

        private func wrappedIndex(_ index: Int) -> Int? {
            guard items.isNotEmpty else { return nil }

            return (index % items.count + items.count) % items.count
        }

        private func selectItem(at index: Int) {
            guard let index = wrappedIndex(index) else { return }

            carouselState.selectedIndex = index
        }

        private static let carouselSettleDuration = 0.2
        private static let detailsRevealDuration = 0.18
    }

    private struct HeroDetails: View {

        let item: BaseItemDto
        @ObservedObject
        var viewModel: HomeViewModel
        let actionViewModel: ItemViewModel?

        var body: some View {
            VStack(alignment: UIDevice.isPad ? .leading : .center, spacing: 18) {
                UpcomingEpisodePillLoader(
                    item: item,
                    userSession: viewModel.userSession
                )

                CinematicLogoImageView(
                    source: logoSource,
                    maxSize: CGSize(width: 260, height: 84),
                    alignment: UIDevice.isPad ? .leading : .center,
                    trimsTransparentPixels: true
                ) {
                    Text(logoFallbackTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(UIDevice.isPad ? .leading : .center)
                }
                .allowsHitTesting(false)

                metadata

                if let actionViewModel {
                    HeroActions(
                        actionItem: item,
                        viewModel: viewModel,
                        itemViewModel: actionViewModel
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: UIDevice.isPad ? .leading : .center)
            .multilineTextAlignment(UIDevice.isPad ? .leading : .center)
            .accessibilityElement(children: .contain)
        }

        @ViewBuilder
        private var metadata: some View {
            DotFlowLayout(
                items: metadataLabels,
                rowAlignment: UIDevice.isPad ? .leading : .center
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
        }

        private var metadataLabels: [String] {
            [typeLabel].compactMap(\.self) + (item.genres ?? [])
        }

        private var typeLabel: String? {
            switch item.type {
            case .series, .episode:
                L10n.tvShow
            case .movie:
                L10n.movie
            default:
                nil
            }
        }

        private var logoSource: ImageSource {
            if item.type == .episode {
                return item.seriesImageSource(.logo, maxWidth: 600)
            }

            return item.imageSource(.logo, maxWidth: 600)
        }

        private var logoFallbackTitle: String {
            if item.type == .episode, let seriesName = item.seriesName {
                return seriesName
            }

            return item.displayTitle
        }
    }

    private struct HeroActions: View {

        let actionItem: BaseItemDto
        @ObservedObject
        var viewModel: HomeViewModel
        @ObservedObject
        var itemViewModel: ItemViewModel

        var body: some View {
            HStack(spacing: FeatureButtonTokens.actionSpacing) {
                PlatformItemView.PlayButton(viewModel: itemViewModel, showsProgressBar: false)

                Button {
                    viewModel.send(.setIsPlayed(!(actionItem.userData?.isPlayed ?? false), actionItem))
                } label: {
                    Image(systemName: actionItem.userData?.isPlayed == true ? "checkmark" : "plus")
                        .id(actionItem.userData?.isPlayed == true)
                        .font(FeatureButtonTokens.labelFont)
                        .transition(.scale.combined(with: .opacity))
                }
                .buttonStyle(.featureIconButton)
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.7),
                    value: actionItem.userData?.isPlayed == true
                )
                .accessibilityLabel(actionItem.userData?.isPlayed == true ? L10n.unplayed : L10n.played)
            }
        }
    }
}
