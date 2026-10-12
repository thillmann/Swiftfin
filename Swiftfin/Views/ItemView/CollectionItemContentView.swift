//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import OrderedCollections
import SwiftUI

// TODO: Show show name in episode subheader

extension PlatformItemView {

    struct CollectionItemContentView: View {

        typealias Element = OrderedDictionary<BaseItemKind, ItemLibraryViewModel>.Elements.Element

        @Router
        private var router

        @ObservedObject
        var viewModel: CollectionItemViewModel

        @State
        private var episodeRailSize: CGSize = .zero

        private var episodeColumnCount: CGFloat {
            if UIDevice.isPhone {
                return 1.5
            }

            return EpisodeCardLayout.iPadColumnCount
        }

        private var episodeRailWidth: CGFloat {
            episodeRailSize.width > 0 ? episodeRailSize.width : UIScreen.main.bounds.width
        }

        private var episodeItemWidth: CGFloat {
            EpisodeCardLayout.itemWidth(for: episodeRailWidth, columns: episodeColumnCount)
        }

        private var episodeRailHeight: CGFloat {
            EpisodeCardLayout.height(for: episodeItemWidth)
        }

        private var orderedSections: [Element] {
            guard viewModel.item.type == .person else {
                return Array(viewModel.sections.elements)
            }

            return [BaseItemKind.movie, .series, .episode].compactMap { kind in
                viewModel.sections[kind].map { (key: kind, value: $0) }
            }
        }

        private func episodeHStack(element: Element) -> some View {
            VStack(alignment: .leading) {

                Text(L10n.episodes)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibility(addTraits: [.isHeader])
                    .edgePadding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: EpisodeCardLayout.itemSpacing) {
                        ForEach(element.value.elements, id: \.unwrappedIDHashOrZero) { episode in
                            SeriesEpisodeSelector.EpisodeCard(episode: episode)
                                .frame(
                                    width: episodeItemWidth,
                                    height: episodeRailHeight,
                                    alignment: .top
                                )
                        }
                    }
                    .padding(.horizontal, EdgeInsets.edgePadding)
                }
                .backport
                .scrollClipDisabled()
                .frame(height: episodeRailHeight)
                .trackingSize($episodeRailSize)
            }
        }

        private func posterHStack(element: Element) -> some View {
            PlatformPosterHStack(
                title: sectionTitle(for: element.key),
                type: element.key.preferredPosterDisplayType,
                items: element.value.elements,
                headerAction: {
                    router.route(to: .library(viewModel: element.value))
                }
            ) { item, namespace in
                router.route(to: .item(item: item), in: namespace)
            }
        }

        private func sectionTitle(for kind: BaseItemKind) -> String {
            if viewModel.item.type == .person, kind == .series {
                return L10n.tvShowsCapitalized
            }

            return kind.pluralDisplayTitle
        }

        @ViewBuilder
        private var itemSections: some View {
            ForEach(orderedSections, id: \.key) { element in
                if element.key == .episode {
                    episodeHStack(element: element)
                } else {
                    posterHStack(element: element)
                }
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: PlatformItemView.detailSectionSpacing) {

                // MARK: - Items

                itemSections

                // MARK: Recommended

                if viewModel.item.type != .person {
                    if viewModel.similarItems.isNotEmpty {
                        PlatformItemView.SimilarItemsHStack(items: viewModel.similarItems)
                    }

                    PlatformItemView.AboutView(viewModel: viewModel)
                }
            }
        }
    }
}
