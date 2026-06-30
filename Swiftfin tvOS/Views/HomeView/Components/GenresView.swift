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

        private struct GenrePalette {
            let background: [Color]
            let tint: Color
            let glow: Color
        }

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
                        Text("Browse by Genre")
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
                    genreArtwork(for: genre)

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
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                }
                .posterStyle(.portrait)
            }
            .buttonStyle(.card)
            .accessibilityLabel(genre.displayTitle)
        }

        private func genreArtwork(for genre: HomeViewModel.Genre) -> some View {
            let palette = genrePalette(for: genre.genre)

            return ZStack {
                if genre.imageSources.isNotEmpty {
                    GeometryReader { proxy in
                        ImageView(genre.imageSources)
                            .image { image in
                                image
                                    .aspectRatio(contentMode: .fill)
                                    .frame(
                                        width: proxy.size.width,
                                        height: proxy.size.height
                                    )
                                    .clipped()
                            }
                            .placeholder { _ in
                                abstractGenreArtwork(palette: palette)
                            }
                            .failure {
                                abstractGenreArtwork(palette: palette)
                            }
                            .frame(
                                width: proxy.size.width,
                                height: proxy.size.height
                            )
                    }
                } else {
                    abstractGenreArtwork(palette: palette)
                }

                RadialGradient(
                    colors: [
                        palette.glow.opacity(0.85),
                        palette.glow.opacity(0.18),
                        .clear,
                    ],
                    center: .topTrailing,
                    startRadius: 8,
                    endRadius: 260
                )
                .blendMode(.screen)

                LinearGradient(
                    colors: [
                        palette.tint.opacity(0.72),
                        palette.tint.opacity(0.18),
                        .clear,
                    ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )

                LinearGradient(
                    colors: [
                        .black.opacity(0.05),
                        .black.opacity(0.34),
                        .black.opacity(0.82),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }

        private func abstractGenreArtwork(palette: GenrePalette) -> some View {
            LinearGradient(
                colors: palette.background,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        private func genrePalette(for genre: UnifiedGenre) -> GenrePalette {
            switch genre.id {
            case "action":
                .init(background: [.orange, .red, .black], tint: .orange, glow: .yellow)
            case "adventure":
                .init(background: [.mint, .green, .black], tint: .green, glow: .cyan)
            case "animation":
                .init(background: [.cyan, .purple, .pink], tint: .pink, glow: .yellow)
            case "comedy":
                .init(background: [.yellow, .green, .black], tint: .green, glow: .yellow)
            case "crime":
                .init(background: [.gray, .blue, .black], tint: .blue, glow: .cyan)
            case "documentary":
                .init(background: [.teal, .blue, .black], tint: .teal, glow: .mint)
            case "drama":
                .init(background: [.blue, .indigo, .black], tint: .blue, glow: .cyan)
            case "family", "kids":
                .init(background: [.pink, .orange, .purple], tint: .pink, glow: .yellow)
            case "fantasy":
                .init(background: [.purple, .indigo, .black], tint: .purple, glow: .mint)
            case "history":
                .init(background: [.brown, .orange, .black], tint: .orange, glow: .yellow)
            case "horror":
                .init(background: [.orange, .black, .black], tint: .orange, glow: .red)
            case "music":
                .init(background: [.pink, .purple, .black], tint: .pink, glow: .cyan)
            case "mystery":
                .init(background: [.indigo, .gray, .black], tint: .indigo, glow: .blue)
            case "news", "talk":
                .init(background: [.blue, .cyan, .black], tint: .blue, glow: .white)
            case "politics", "war":
                .init(background: [.gray, .red, .black], tint: .red, glow: .orange)
            case "reality":
                .init(background: [.purple, .pink, .black], tint: .purple, glow: .pink)
            case "romance":
                .init(background: [.pink, .red, .black], tint: .pink, glow: .orange)
            case "science-fiction":
                .init(background: [.cyan, .indigo, .black], tint: .cyan, glow: .teal)
            case "soap":
                .init(background: [.mint, .teal, .black], tint: .teal, glow: .white)
            case "thriller":
                .init(background: [.red, .purple, .black], tint: .red, glow: .orange)
            case "western":
                .init(background: [.orange, .brown, .black], tint: .brown, glow: .yellow)
            default:
                .init(background: [.teal, .purple, .black], tint: .teal, glow: .white)
            }
        }

        private func route(to genre: HomeViewModel.Genre) {
            didSelectGenre()

            router.route(to: .genreLibrary(genre: genre.genre))
        }

        func onSelectGenre(_ action: @escaping () -> Void) -> Self {
            var copy = self
            copy.didSelectGenre = action
            return copy
        }
    }
}
