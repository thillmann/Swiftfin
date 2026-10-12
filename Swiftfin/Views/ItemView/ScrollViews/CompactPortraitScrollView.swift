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

    struct CompactPosterScrollView<Content: View>: ScrollContainerView {

        @Router
        private var router

        @ObservedObject
        private var viewModel: ItemViewModel

        private let content: Content

        init(
            viewModel: ItemViewModel,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.content = content()
            self.viewModel = viewModel
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

            let imageType: ImageType = item.type == .episode ? .primary : .backdrop
            let bottomColor = item.blurHash(for: imageType)?.averageLinearColor ?? Color.secondarySystemFill
            let imageSource = viewModel.isOffline
                ? viewModel.imageSource(imageType, maxWidth: 1320)
                : item.imageSource(imageType, maxWidth: 1320)

            return content(imageSource, bottomColor)
                .id(imageSource.url?.hashValue)
                .animation(.linear(duration: 0.1), value: imageSource.url?.hashValue)
        }

        @ViewBuilder
        private var headerView: some View {
            GeometryReader { proxy in
                withHeaderImageItem { imageSource, bottomColor in
                    ImageView(imageSource)
                        .aspectRatio(1.77, contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height * 0.78, alignment: .top)
                        .bottomEdgeGradient(bottomColor: bottomColor)
                }
            }
        }

        var body: some View {
            OffsetScrollView(heightRatio: 0.45) {
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
                SeparatorVStack(alignment: .leading) {
                    RowDivider()
                        .padding(.vertical, 10)
                } content: {
                    content
                }
                .padding(.top, PlatformItemView.detailSectionSpacing)
                .edgePadding(.bottom)
            }
        }
    }
}

// TODO: have action buttons part of the right shelf view
//       - possible on leading edge instead

extension PlatformItemView.CompactPosterScrollView {

    struct OverlayView: View {

        @StoredValue(.User.itemViewAttributes)
        private var attributes

        @Router
        private var router

        @ObservedObject
        var viewModel: ItemViewModel

        @ViewBuilder
        private var rightShelfView: some View {
            VStack(alignment: .leading) {

                Text(viewModel.item.displayTitle)
                    .font(.title2)
                    .lineLimit(2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                DotHStack {
                    if viewModel.item.type == .person {
                        if let birthday = viewModel.item.birthday {
                            Text(
                                birthday,
                                format: .age.death(viewModel.item.deathday)
                            )
                        }
                    } else {
                        if viewModel.item.isUnaired {
                            if let premiereDateLabel = viewModel.item.airDateLabel {
                                Text(premiereDateLabel)
                            }
                        } else {
                            if let productionYear = viewModel.item.premiereDateYear {
                                Text(String(productionYear))
                            }
                        }

                        if let playButtonitem = viewModel.playButtonItem, let runtime = playButtonitem.runTimeLabel {
                            Text(runtime)
                        }
                    }
                }
                .lineLimit(1)
                .font(.subheadline.weight(.medium))
                .foregroundColor(Color(UIColor.lightGray))

                PlatformItemView.AttributesHStack(
                    attributes: attributes,
                    viewModel: viewModel,
                    alignment: .leading
                )
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 12) {

                    PlatformPosterImage(
                        item: viewModel.item,
                        type: .portrait,
                        contentMode: .fit,
                        imageSources: viewModel.isOffline
                            ? [viewModel.imageSource(.primary, maxWidth: 600)]
                            : nil
                    )
                    .withViewContext(.isOverComplexContent)
                    .frame(width: 130)
                    .accessibilityIgnoresInvertColors()

                    rightShelfView
                        .padding(.bottom)
                }

                HStack(alignment: .center) {

                    if viewModel.item.presentPlayButton {
                        PlatformItemView.PlayButton(viewModel: viewModel)
                            .frame(width: 130)
                    }

                    Spacer()

                    PlatformItemView.ActionButtonHStack(viewModel: viewModel, equalSpacing: false)
                        .foregroundStyle(.white)
                }
                .frame(height: 45)
            }
        }
    }
}
