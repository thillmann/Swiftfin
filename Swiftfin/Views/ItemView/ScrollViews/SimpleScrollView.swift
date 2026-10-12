//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import BlurHashKit
import JellyfinAPI
import SwiftUI

extension PlatformItemView {

    struct SimpleScrollView<Content: View>: ScrollContainerView {

        @StoredValue(.User.itemViewAttributes)
        private var attributes

        @Router
        private var router

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

        @ViewBuilder
        private var shelfView: some View {
            VStack(alignment: .center, spacing: 16) {
                VStack(spacing: 8) {
                    VStack(spacing: 4) {
                        if let parentTitle = viewModel.item.parentTitle {
                            if let seriesID = viewModel.item.seriesID, !viewModel.isOffline {
                                Button {
                                    router.route(
                                        to: .item(
                                            item: .init(
                                                id: seriesID,
                                                name: parentTitle,
                                                type: .series
                                            )
                                        )
                                    )
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(parentTitle)

                                        Image(systemName: "chevron.right")
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .padding(.horizontal)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(parentTitle)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .padding(.horizontal)
                            }
                        }

                        Text(viewModel.item.displayTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal)
                    }

                    if let genres = viewModel.item.genres, genres.isNotEmpty {
                        DotFlowLayout(items: genres)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal)
                    }
                }

                if viewModel.item.presentPlayButton || (viewModel.item.canBePlayed && !viewModel.isOffline) {
                    HStack(spacing: FeatureButtonTokens.actionSpacing) {
                        if viewModel.item.presentPlayButton {
                            PlatformItemView.PlayButton(viewModel: viewModel)
                                .frame(height: 50)
                        }

                        if viewModel.item.canBePlayed, !viewModel.isOffline {
                            PlatformItemView.FeatureUserDataButton(viewModel: viewModel, action: .played)
                        }
                    }
                }

                synopsis

                metadata
            }
        }

        @ViewBuilder
        private var synopsis: some View {
            if let overview = viewModel.item.overview, overview.isNotEmpty {
                let prefix = viewModel.item.seasonEpisodeLabel.map { "\($0): " } ?? ""

                (Text(prefix).fontWeight(.bold) + Text(overview))
                    .font(.callout)
                    .foregroundStyle(Color(white: 0.75))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }

        private var metadata: some View {
            PlatformItemView.AttributesHStack(
                attributes: attributes,
                viewModel: viewModel,
                alignment: .leading,
                flowDirection: .down,
                leadingContent: AnyView(
                    DotHStack {
                        if let premiereDateLabel = viewModel.item.premiereDateLabel {
                            Text(premiereDateLabel)
                        }

                        if let runtime = viewModel.item.runTimeLabel {
                            Text(runtime)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.callout)
                    .foregroundStyle(.white)
                )
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // TODO: remove and just use `PlatformPosterImage` with landscape
        //       after poster environment implemented
        private var imageType: ImageType {
            switch viewModel.item.type {
            case .episode, .musicVideo, .video:
                .primary
            default:
                .backdrop
            }
        }

        @ViewBuilder
        private var header: some View {
            VStack(alignment: .center) {
                ZStack {
                    Rectangle()
                        .fill(.complexSecondary)

                    ImageView(viewModel.imageSource(imageType, maxWidth: 600))
                        .failure {
                            SystemImageContentView(systemName: viewModel.item.systemImage)
                        }
                }
                .aspectRatio(1.77, contentMode: .fit)
                .frame(maxWidth: .infinity)

                shelfView
                    .edgePadding(.horizontal)
                    .padding(.top, 16)
            }
        }

        var body: some View {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PlatformItemView.detailSectionSpacing) {

                    header
                        .padding(.top, 4)

                    content
                        .edgePadding(.bottom)
                }
            }
        }
    }
}
