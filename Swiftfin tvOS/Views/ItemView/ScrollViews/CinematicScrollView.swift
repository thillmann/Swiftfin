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

    struct CinematicScrollView<Content: View>: ScrollContainerView {

        @ObservedObject
        private var viewModel: ItemViewModel

        @StateObject
        private var focusGuide = FocusGuide()
        @State
        private var collapsesSeriesHero = false
        @State
        private var hasEstablishedSeriesHeaderFocus = false

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

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            CinematicHeaderView(viewModel: viewModel)
                                .ifLet(viewModel as? SeriesItemViewModel) { view, _ in
                                    view
                                        .focusGuide(
                                            focusGuide,
                                            tag: "header",
                                            bottom: "belowHeader"
                                        )
                                }
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
                        .environmentObject(focusGuide)
                    }
                }
                .onAppear {
                    hasEstablishedSeriesHeaderFocus = false
                    updateSeriesHeroCollapse(for: focusGuide.focusedTag)
                }
                .onChange(of: focusGuide.focusedTag) { _, newTag in
                    updateSeriesHeroCollapse(for: newTag)
                }
            }
            .ignoresSafeArea()
        }

        private func updateSeriesHeroCollapse(for focusedTag: String?) {
            guard viewModel.item.type == .series else {
                collapsesSeriesHero = false
                hasEstablishedSeriesHeaderFocus = false
                return
            }

            if focusedTag == "header" {
                hasEstablishedSeriesHeaderFocus = true
                collapsesSeriesHero = false
                return
            }

            let shouldCollapse = focusedTag == "belowHeader" || focusedTag == "episodes"
            collapsesSeriesHero = hasEstablishedSeriesHeaderFocus && shouldCollapse
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

        @StoredValue(.User.itemViewAttributes)
        private var attributes

        @ObservedObject
        var viewModel: ItemViewModel
        @FocusState
        private var focusedLayer: CinematicHeaderFocusLayer?

        private var heroTitleFallback: some View {
            Text(viewModel.item.displayTitle)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: 800, alignment: .leading)
        }

        private var heroOverviewItem: BaseItemDto {
            if let seriesViewModel = viewModel as? SeriesItemViewModel,
               let episodeOverviewItem = seriesViewModel.episodeOverviewItem,
               let overview = episodeOverviewItem.overview,
               !overview.isEmpty
            {
                return episodeOverviewItem
            }

            return viewModel.item
        }

        @ViewBuilder
        private var heroLogoOrTitle: some View {
            if viewModel.item.imageURL(.logo, maxHeight: 200) != nil {
                ImageView(viewModel.item.imageSource(.logo, maxHeight: 200))
                    .placeholder { _ in
                        EmptyView()
                    }
                    .failure {
                        heroTitleFallback
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400, maxHeight: 200, alignment: .leading)
            } else {
                heroTitleFallback
            }
        }

        var body: some View {
            VStack(alignment: .trailing, spacing: 0) {

                Color.clear
                    .focusable()
                    .focused($focusedLayer, equals: .top)

                HStack(alignment: .bottom, spacing: 80) {
                    VStack(alignment: .leading, spacing: 24) {
                        heroLogoOrTitle

                        DotHStack {
                            if viewModel.item.type == .series {
                                Text(L10n.series)
                            } else if viewModel.item.type == .episode {
                                Text(L10n.episode)
                            }

                            ForEach(viewModel.item.genres ?? [], id: \.self) { value in
                                Text(value)
                            }
                        }
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))

                        OverviewView(item: heroOverviewItem)
                            .taglineLineLimit(1)
                            .overviewLineLimit(3)
                            .frame(maxWidth: 800, alignment: .leading)

                        if viewModel.item.type != .person {
                            HStack(spacing: 20) {
                                DotHStack {
                                    Text(viewModel.item.premiereDateYear)
                                    Text(viewModel.playButtonItem?.runTimeLabel)
                                }
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.9))

                                ItemView.AttributesHStack(
                                    attributes: attributes,
                                    viewModel: viewModel
                                )
                            }

                            HStack(spacing: 20) {
                                if viewModel.item.presentPlayButton {
                                    ItemView.PlayButton(viewModel: viewModel)
                                        .focused($focusedLayer, equals: .playButton)
                                }

                                ItemView.ActionButtonHStack(viewModel: viewModel)
                                    .focused($focusedLayer, equals: .actionButtons)
                            }
                            .frame(width: 800, alignment: .leading)
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
            .onChange(of: focusedLayer) { _, layer in
                if layer == .top {
                    if viewModel.item.type == .person {
                        return
                    }

                    if viewModel.item.presentPlayButton {
                        focusedLayer = .playButton
                    } else {
                        focusedLayer = .actionButtons
                    }
                }
            }
        }
    }
}
