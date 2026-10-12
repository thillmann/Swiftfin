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

extension PlatformItemView {

    struct CinematicScrollView<Content: View>: ScrollContainerView {

        @Default(.Customization.CinematicItemViewType.usePrimaryImage)
        private var usePrimaryImage

        @Router
        private var router

        @ObservedObject
        private var viewModel: ItemViewModel

        private let content: Content

        init(
            viewModel: ItemViewModel,
            content: @escaping () -> Content
        ) {
            self.content = content()
            self.viewModel = viewModel
        }

        private var imageType: ImageType {
            usePrimaryImage ? .primary : .backdrop
        }

        @ViewBuilder
        private var headerView: some View {

            let bottomColor = viewModel.item.blurHash(for: imageType)?.averageLinearColor ?? Color.secondarySystemFill

            GeometryReader { proxy in
                if proxy.size.height.isZero { EmptyView() }
                else {
                    let headerSize = CGSize(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    let displayedAspectRatio: CGFloat = usePrimaryImage ? (2 / 3) : 1.77
                    let requestedWidth = max(
                        headerSize.width,
                        headerSize.height * displayedAspectRatio
                    )

                    if usePrimaryImage {
                        ImageView(viewModel.imageSource(
                            imageType,
                            maxWidth: requestedWidth
                        ))
                        .aspectRatio(displayedAspectRatio, contentMode: .fill)
                        .frame(width: headerSize.width, height: headerSize.height)
                        .clipped()
                        .bottomEdgeGradient(bottomColor: bottomColor)
                    } else {
                        CinematicBackdropView(
                            source: viewModel.imageSource(
                                .backdrop,
                                maxWidth: max(1200, headerSize.height * 1.77)
                            ),
                            bottomColor: bottomColor,
                            size: headerSize
                        )
                    }
                }
            }
        }

        var body: some View {
            OffsetScrollView(heightRatio: 0.8) {
                headerView
            } overlay: {
                ZStack(alignment: .bottom) {
                    CinematicHeroBlurOverlay()

                    OverlayView(viewModel: viewModel)
                        .edgePadding(.horizontal)
                        .edgePadding(.bottom)
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

extension PlatformItemView.CinematicScrollView {

    struct OverlayView: View {

        @StoredValue(.User.itemViewAttributes)
        private var attributes

        @Router
        private var router

        @ObservedObject
        var viewModel: ItemViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 18) {
                    upcomingEpisodePill

                    logo

                    mediaTypeAndGenres

                    actions
                }
                .frame(maxWidth: .infinity)

                description

                releaseMetadata
            }
            .frame(maxWidth: .infinity)
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
                alignment: .center,
                trimsTransparentPixels: true
            ) {
                Text(viewModel.item.displayTitle)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
            }
            .allowsHitTesting(false)
        }

        private var mediaTypeAndGenres: some View {
            DotFlowLayout(items: metadataLabels)
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
            .foregroundColor(Color(UIColor.lightGray))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }

        private var isWatched: Bool {
            viewModel.item.userData?.isPlayed == true
        }
    }
}
