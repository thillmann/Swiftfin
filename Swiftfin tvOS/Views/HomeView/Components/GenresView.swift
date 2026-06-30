//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension HomeView {

    struct GenresView: View {

        @Router
        private var router

        let genres: [HomeViewModel.Genre]

        private var didSelectGenre: () -> Void = {}

        @State
        private var contentSize: CGSize = .zero

        private let horizontalPadding: CGFloat = EdgeInsets.edgePadding
        private let itemSpacing: CGFloat = EdgeInsets.edgePadding - 40
        private let verticalPadding: CGFloat = 20

        init(genres: [HomeViewModel.Genre]) {
            self.genres = genres
        }

        private var itemWidth: CGFloat {
            let availableWidth = contentSize.width > 0 ? contentSize.width : UIScreen.main.bounds.width
            let width = (
                availableWidth - horizontalPadding * 2 - itemSpacing * 5
            ) / 6

            return max(width, 1)
        }

        private var itemHeight: CGFloat {
            itemWidth / (2 / 3)
        }

        private var rowHeight: CGFloat {
            itemHeight + verticalPadding * 2
        }

        var body: some View {
            if genres.isNotEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text(L10n.genres)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .accessibility(addTraits: [.isHeader])
                            .padding(.leading, 80)

                        Spacer()
                    }

                    ScrollView(.horizontal) {
                        LazyHStack(spacing: itemSpacing) {
                            ForEach(genres) { genre in
                                genreButton(genre)
                                    .frame(width: itemWidth, height: itemHeight)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, verticalPadding)
                    }
                    .frame(height: rowHeight)
                    .scrollClipDisabled()
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                }
                .trackingSize($contentSize)
                .focusSection()
            }
        }

        private func genreButton(_ genre: HomeViewModel.Genre) -> some View {
            Button {
                route(to: genre)
            } label: {
                ZStack {
                    PosterImage(
                        item: genre.posterItem,
                        type: .portrait
                    )

                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.18),
                            .black.opacity(0.78),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack {
                        Spacer(minLength: 0)

                        Text(genre.displayTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(16)
                }
                .posterStyle(.portrait)
            }
            .buttonStyle(.card)
            .accessibilityLabel(genre.displayTitle)
        }

        private func route(to genre: HomeViewModel.Genre) {
            didSelectGenre()

            if SeerrIntegration.isAvailable,
               SeerrGenreMapper.mapping(for: genre.genre) != nil
            {
                router.route(to: .genreLibrary(genre: genre.genre))
            } else {
                let parent = TitledLibraryParent(
                    displayTitle: genre.displayTitle,
                    id: genre.genre.id ?? genre.genre.value
                )
                let viewModel = ItemLibraryViewModel(
                    parent: parent,
                    filters: .init(
                        genres: [genre.genre],
                        itemTypes: [.movie, .series]
                    )
                )
                router.route(to: .library(viewModel: viewModel))
            }
        }

        func onSelectGenre(_ action: @escaping () -> Void) -> Self {
            var copy = self
            copy.didSelectGenre = action
            return copy
        }
    }
}
