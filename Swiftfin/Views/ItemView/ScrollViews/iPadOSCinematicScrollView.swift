//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension PlatformItemView {

    struct iPadOSCinematicScrollView<Content: View>: ScrollContainerView {

        @ObservedObject
        private var viewModel: ItemViewModel

        private let content: Content

        init(
            viewModel: ItemViewModel,
            @ViewBuilder content: () -> Content
        ) {
            self.content = content()
            self.viewModel = viewModel
        }

        private var imageType: ImageType {
            switch viewModel.item.type {
            case .episode, .musicVideo, .video:
                .primary
            default:
                .backdrop
            }
        }

        private func withHeaderImageItem(
            @ViewBuilder content: @escaping (ImageSource, Color) -> some View
        ) -> some View {

            let item: BaseItemDto = if viewModel.item.type == .person || viewModel.item.type == .musicArtist,
                                       let typeViewModel = viewModel as? CollectionItemViewModel,
                                       let randomItem = typeViewModel.randomItem()
            {
                randomItem
            } else {
                viewModel.item
            }

            let bottomColor = item.blurHash(for: imageType)?.averageLinearColor ?? Color.secondarySystemFill
            let imageSource = viewModel.isOffline
                ? viewModel.imageSource(imageType, maxWidth: 1920)
                : item.imageSource(imageType, maxWidth: 1920)

            return content(imageSource, bottomColor)
                .id(imageSource.url?.hashValue)
                .animation(.linear(duration: 0.1), value: imageSource.url?.hashValue)
        }

        @ViewBuilder
        private var headerView: some View {
            withHeaderImageItem { imageSource, bottomColor in
                GeometryReader { proxy in
                    if proxy.size.height.isZero {
                        EmptyView()
                    } else {
                        CinematicBackdropView(
                            source: imageSource,
                            bottomColor: bottomColor,
                            size: proxy.size
                        )
                    }
                }
            }
        }

        var body: some View {
            OffsetScrollView(heightRatio: 0.8, portraitHeightRatio: 0.4) {
                headerView
            } overlay: {
                ZStack(alignment: .bottom) {
                    CinematicHeroBlurOverlay()

                    OverlayView(viewModel: viewModel)
                        .edgePadding()
                        .frame(maxWidth: .infinity)
                }
            } content: {
                content
                    .padding(.top, PlatformItemView.detailSectionSpacing)
                    .edgePadding(.bottom)
            }
        }
    }
}

extension PlatformItemView.iPadOSCinematicScrollView {

    struct OverlayView: View {

        @StoredValue(.User.itemViewAttributes)
        private var attributes

        @Router
        private var router

        @ObservedObject
        var viewModel: ItemViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 18) {
                    upcomingEpisodePill

                    logo

                    mediaTypeAndGenres

                    actions
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                description
                    .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                        width * 0.5
                    }

                releaseMetadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        @ViewBuilder
        private var upcomingEpisodePill: some View {
            if let label = (viewModel as? SeriesItemViewModel)?.upcomingEpisodePillLabel {
                UpcomingEpisodePill(label: label)
            }
        }

        private var logo: some View {
            CinematicLogoImageView(
                source: viewModel.imageSource(.logo, maxWidth: 600),
                maxSize: CGSize(width: 260, height: 84),
                alignment: .leading,
                trimsTransparentPixels: true
            ) {
                Text(viewModel.item.displayTitle)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.white)
            }
            .allowsHitTesting(false)
        }

        private var mediaTypeAndGenres: some View {
            DotFlowLayout(items: metadataLabels, rowAlignment: .leading)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
        }

        private var metadataLabels: [String] {
            [viewModel.item.type == .movie ? L10n.movie : L10n.tvShow] + (viewModel.item.genres ?? [])
        }

        private var actions: some View {
            HStack(spacing: FeatureButtonTokens.actionSpacing) {
                if viewModel.item.presentPlayButton {
                    PlatformItemView.PlayButton(viewModel: viewModel)
                }

                if viewModel.item.canBePlayed, !viewModel.isOffline {
                    PlatformItemView.FeatureUserDataButton(viewModel: viewModel, action: .played)
                    PlatformItemView.FeatureUserDataButton(viewModel: viewModel, action: .favorite)
                }
            }
        }

        @ViewBuilder
        private var description: some View {
            let item = descriptionItem

            if let overview = item.overview {
                TruncatedText(prefix: item.seasonEpisodeLabel.map { "\($0): " }, overview)
                    .onSeeMore {
                        router.route(to: .itemOverview(item: item))
                    }
                    .seeMoreType(.pill)
                    .lineLimit(2)
                    .font(.callout)
                    .foregroundColor(Color(UIColor.lightGray))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private var descriptionItem: BaseItemDto {
            (viewModel as? SeriesItemViewModel)?.episodeOverviewItem ?? viewModel.item
        }

        private var releaseMetadata: some View {
            DotHStack {
                if let premiereYear = viewModel.item.premiereDateYear {
                    Text(premiereYear)
                        .fixedSize(horizontal: true, vertical: false)
                }

                HStack(spacing: 10) {
                    if let runtime = viewModel.playButtonItem?.runTimeLabel {
                        Text(runtime)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    PlatformItemView.AttributesHStack(
                        attributes: attributes,
                        viewModel: viewModel,
                        alignment: .leading,
                        limitToCinematicBadges: true
                    )
                    .font(.caption2)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .font(.callout)
            .foregroundStyle(Color(UIColor.lightGray))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }

        private var isWatched: Bool {
            viewModel.item.userData?.isPlayed == true
        }
    }
}
