//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension ItemView {

    enum CinematicFocusRegion {
        case header
        case belowHeader
        case episodes
    }

    enum CinematicScrollTarget: Hashable {
        case header
        case episodeSelector
    }

    struct CinematicFocusRegionActionKey: EnvironmentKey {
        static let defaultValue: (CinematicFocusRegion) -> Void = { _ in }
    }

    struct CinematicScrollTargetActionKey: EnvironmentKey {
        static let defaultValue: (CinematicScrollTarget) -> Void = { _ in }
    }
}

extension EnvironmentValues {
    var cinematicFocusRegionChanged: (ItemView.CinematicFocusRegion) -> Void {
        get { self[ItemView.CinematicFocusRegionActionKey.self] }
        set { self[ItemView.CinematicFocusRegionActionKey.self] = newValue }
    }

    var cinematicScrollTargetRequested: (ItemView.CinematicScrollTarget) -> Void {
        get { self[ItemView.CinematicScrollTargetActionKey.self] }
        set { self[ItemView.CinematicScrollTargetActionKey.self] = newValue }
    }
}

extension ItemView {

    struct CinematicScrollView<Content: View>: ScrollContainerView {

        @ObservedObject
        private var viewModel: ItemViewModel

        @State
        private var collapsesSeriesHero = false
        @State
        private var hasEstablishedSeriesHeaderFocus = false
        @State
        private var lastRequestedScrollTarget: CinematicScrollTarget?

        private let content: Content

        init(
            viewModel: ItemViewModel,
            content: @escaping () -> Content
        ) {
            self.viewModel = viewModel
            self.content = content()
        }

        private func withBackgroundImageSource(
            @ViewBuilder content: @escaping (ImageSource) -> some View
        ) -> some View {
            let item: BaseItemDto = if viewModel.item.type == .person || viewModel.item.type == .musicArtist,
                                       let typeViewModel = viewModel as? CollectionItemViewModel,
                                       let randomItem = typeViewModel.randomItem()
            {
                randomItem
            } else {
                viewModel.item
            }

            let imageType: ImageType = {
                switch item.type {
                case .episode, .musicVideo, .video:
                    .primary
                default:
                    .backdrop
                }
            }()

            let imageSource = item.imageSource(imageType, maxWidth: 1920)

            return content(imageSource)
                .id(imageSource.url?.hashValue)
                .animation(.linear(duration: 0.1), value: imageSource.url?.hashValue)
        }

        var body: some View {
            GeometryReader { proxy in
                let expandedHeaderHeight = max(proxy.size.height - 150, 0)
                let collapseProgress: CGFloat = (viewModel.item.type == .series && collapsesSeriesHero) ? 1 : 0
                let visibleHeaderHeight = expandedHeaderHeight * (1 - collapseProgress)
                let visibleBottomPadding = 50 * (1 - collapseProgress)

                ZStack {
                    withBackgroundImageSource { imageSource in
                        ImageView(imageSource)
                    }

                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                CinematicHeaderView(viewModel: viewModel)
                                    .id(CinematicScrollTarget.header)
                                    .frame(height: expandedHeaderHeight, alignment: .top)
                                    .offset(y: -expandedHeaderHeight * collapseProgress)
                                    .frame(height: visibleHeaderHeight, alignment: .top)
                                    .padding(.bottom, visibleBottomPadding)
                                    .clipped()
                                    .animation(.easeOut(duration: 0.25), value: collapsesSeriesHero)

                                content
                            }
                            .background {
                                BlurView(style: .dark)
                                    .mask {
                                        VStack(spacing: 0) {
                                            LinearGradient(gradient: Gradient(stops: [
                                                .init(color: .white, location: 0),
                                                .init(color: .white.opacity(0.7), location: 0.4),
                                                .init(color: .white.opacity(0), location: 1),
                                            ]), startPoint: .bottom, endPoint: .top)
                                                .frame(height: proxy.size.height - 150)

                                            Color.white
                                        }
                                    }
                            }
                            .environment(\.cinematicFocusRegionChanged) { region in
                                updateSeriesHeroCollapse(for: region)
                            }
                            .environment(\.cinematicScrollTargetRequested) { target in
                                scrollToTarget(target, proxy: scrollProxy)
                            }
                        }
                    }
                }
                .onAppear {
                    hasEstablishedSeriesHeaderFocus = false
                    collapsesSeriesHero = false
                    lastRequestedScrollTarget = nil
                }
            }
            .ignoresSafeArea()
        }

        private func updateSeriesHeroCollapse(for focusedRegion: CinematicFocusRegion) {
            guard viewModel.item.type == .series else {
                collapsesSeriesHero = false
                hasEstablishedSeriesHeaderFocus = false
                lastRequestedScrollTarget = nil
                return
            }

            if focusedRegion == .header {
                hasEstablishedSeriesHeaderFocus = true
                collapsesSeriesHero = false
                lastRequestedScrollTarget = nil
                return
            }

            let shouldCollapse = focusedRegion == .episodes
            collapsesSeriesHero = hasEstablishedSeriesHeaderFocus && shouldCollapse
        }

        private func scrollToTarget(_ target: CinematicScrollTarget, proxy: ScrollViewProxy) {
            guard canScroll(to: target),
                  target != lastRequestedScrollTarget
            else { return }

            lastRequestedScrollTarget = target

            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.4)) {
                    proxy.scrollTo(target, anchor: anchor(for: target))
                }
            }
        }

        private func canScroll(to target: CinematicScrollTarget) -> Bool {
            switch target {
            case .header:
                true
            case .episodeSelector:
                viewModel.item.type == .series
            }
        }

        private func anchor(for target: CinematicScrollTarget) -> UnitPoint {
            switch target {
            case .header:
                .top
            case .episodeSelector:
                UnitPoint(x: 0.5, y: 0.15)
            }
        }
    }
}

extension ItemView {

    struct CinematicHeaderView: View {

        enum CinematicHeaderFocusLayer: Hashable {
            case top
            case playButton
            case actionButtons
        }

        @ObservedObject
        var viewModel: ItemViewModel
        @Environment(\.cinematicFocusRegionChanged)
        private var focusRegionChanged
        @Environment(\.cinematicScrollTargetRequested)
        private var scrollTargetRequested
        @FocusState
        private var focusedLayer: CinematicHeaderFocusLayer?
        @State
        private var allowsInitialHeaderFocusRepair = true
        @State
        private var didApplyInitialHeaderFocus = false

        private var upcomingEpisodePillLabel: String? {
            guard let seriesViewModel = viewModel as? SeriesItemViewModel else {
                return nil
            }

            return seriesViewModel.upcomingEpisodePillLabel
        }

        private var heroItem: BaseItemDto {
            guard let seriesViewModel = viewModel as? SeriesItemViewModel,
                  let episodeOverviewItem = seriesViewModel.episodeOverviewItem
            else {
                return viewModel.item
            }

            return episodeOverviewItem
        }

        private var preferredHeaderFocusLayer: CinematicHeaderFocusLayer? {
            guard viewModel.item.type != .person else { return nil }

            if viewModel.item.presentPlayButton {
                return .playButton
            }

            return .actionButtons
        }

        private var isPreferredHeaderFocusReady: Bool {
            switch preferredHeaderFocusLayer {
            case .playButton:
                viewModel.playButtonItem != nil && viewModel.selectedMediaSource != nil
            case .actionButtons:
                true
            case nil:
                false
            case .top:
                false
            }
        }

        private func focusPrimaryHeaderControl() {
            if viewModel.item.type == .person {
                return
            }

            if viewModel.item.presentPlayButton {
                focusedLayer = .playButton
            } else {
                focusedLayer = .actionButtons
            }
        }

        private func focusPreferredHeaderControlIfNeeded(forceIfUnclaimed: Bool = false) {
            guard allowsInitialHeaderFocusRepair,
                  isPreferredHeaderFocusReady,
                  let preferredHeaderFocusLayer,
                  focusedLayer == nil || focusedLayer == preferredHeaderFocusLayer || (!didApplyInitialHeaderFocus && forceIfUnclaimed)
            else { return }

            DispatchQueue.main.async {
                guard allowsInitialHeaderFocusRepair,
                      isPreferredHeaderFocusReady,
                      focusedLayer == nil || focusedLayer == preferredHeaderFocusLayer || (!didApplyInitialHeaderFocus && forceIfUnclaimed)
                else { return }

                focusedLayer = preferredHeaderFocusLayer
            }
        }

        var body: some View {
            VStack(alignment: .trailing, spacing: 0) {

                Color.clear
                    .focusable()
                    .focused($focusedLayer, equals: .top)

                HStack(alignment: .bottom, spacing: 80) {
                    CinematicItemHeroView(
                        item: heroItem,
                        itemViewModel: viewModel
                    ) { itemViewModel in
                        if viewModel.item.type != .person {
                            if viewModel.item.presentPlayButton {
                                ItemView.PlayButton(viewModel: itemViewModel)
                                    .focused($focusedLayer, equals: .playButton)
                            }

                            ItemView.ActionButtonHStack(viewModel: itemViewModel)
                                .focused($focusedLayer, equals: .actionButtons)
                        }
                    } accessory: {
                        if let upcomingEpisodePillLabel {
                            UpcomingEpisodePill(label: upcomingEpisodePillLabel)
                        }
                    }

                    Spacer(minLength: 0)

                    if viewModel.item.type == .person || viewModel.item.type == .musicArtist {
                        VStack(spacing: 30) {
                            ImageView(viewModel.item.imageSource(.primary, maxWidth: 450))
                                .failure {
                                    SystemImageContentView(systemName: viewModel.item.systemImage)
                                }
                                .posterStyle(.portrait, contentMode: .fill)
                                .cornerRadius(10)
                                .accessibilityIgnoresInvertColors()
                        }
                        .frame(width: 450)
                        .padding(.leading, 150)
                    }
                }
            }
            .padding(.leading, 80)
            .padding(.trailing, 50)
            .defaultFocus(
                $focusedLayer,
                preferredHeaderFocusLayer,
                priority: .userInitiated
            )
            .onAppear {
                focusPreferredHeaderControlIfNeeded(forceIfUnclaimed: true)
            }
            .onReceive(viewModel.playButtonItem.publisher) { _ in
                focusPreferredHeaderControlIfNeeded(forceIfUnclaimed: true)
            }
            .onReceive(viewModel.objectWillChange) { _ in
                DispatchQueue.main.async {
                    focusPreferredHeaderControlIfNeeded(forceIfUnclaimed: true)
                }
            }
            .onChange(of: focusedLayer) { _, layer in
                if layer == .top {
                    focusPrimaryHeaderControl()
                    return
                }

                guard let layer else {
                    if didApplyInitialHeaderFocus {
                        allowsInitialHeaderFocusRepair = false
                    }
                    return
                }

                if layer == preferredHeaderFocusLayer {
                    didApplyInitialHeaderFocus = true
                } else if didApplyInitialHeaderFocus {
                    allowsInitialHeaderFocusRepair = false
                }

                focusRegionChanged(.header)
                scrollTargetRequested(.header)
            }
        }
    }

    private struct UpcomingEpisodePill: View {

        let label: String

        var body: some View {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 24)
                .frame(height: 52)
                .background {
                    Capsule(style: .continuous)
                        .fill(.black.opacity(0.38))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
}
