//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ItemView {

    struct SeriesDetailView: View {

        @EnvironmentObject
        private var focusGuide: FocusGuide
        @EnvironmentObject
        private var choreography: SeriesScrollChoreographyModel

        @FocusState
        private var focusedPlaceholderID: String?

        @ObservedObject
        var viewModel: SeriesItemViewModel

        let showsLegacyEpisodeSelector: Bool

        init(
            viewModel: SeriesItemViewModel,
            showsLegacyEpisodeSelector: Bool = false
        ) {
            self.viewModel = viewModel
            self.showsLegacyEpisodeSelector = showsLegacyEpisodeSelector
        }

        private var seasonTitles: [String] {
            let loadedTitles = viewModel.seasons.prefix(4).map(\.season.displayTitle)
            return loadedTitles.isEmpty ? ["Season 1", "Season 2", "Season 3"] : loadedTitles
        }

        private var heroMetadata: [String] {
            var values = [L10n.series]

            if let firstGenre = viewModel.item.genres?.first {
                values.append(firstGenre)
            }

            if let premiereYear = viewModel.item.premiereDateYear {
                values.append(premiereYear)
            }

            if let runtime = viewModel.playButtonItem?.runTimeLabel {
                values.append(runtime)
            }

            return values
        }

        private var heroSection: some View {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 80) {
                    VStack(alignment: .leading, spacing: 24) {
                        ImageView(viewModel.item.imageSource(.logo, maxHeight: 240))
                            .placeholder { _ in
                                EmptyView()
                            }
                            .failure {
                                Text(viewModel.item.displayTitle)
                                    .font(.system(size: 64, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                            }
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 760, alignment: .leading)

                        DotHStack {
                            ForEach(heroMetadata, id: \.self) { value in
                                Text(value)
                            }
                        }
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.75))

                        OverviewView(item: viewModel.item)
                            .taglineLineLimit(1)
                            .overviewLineLimit(3)
                            .frame(maxWidth: 760, alignment: .leading)
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 24) {
                        if viewModel.item.presentPlayButton {
                            ItemView.PlayButton(viewModel: viewModel)
                                .frame(height: 100)
                        }

                        ItemView.ActionButtonHStack(viewModel: viewModel)
                            .frame(width: 460, height: 100)
                    }
                    .frame(width: 500, alignment: .trailing)
                }
                .focusGuide(focusGuide, tag: "seriesHero", bottom: "seriesEpisodes")
            }
            .padding(.horizontal, 65)
            .padding(.top, 120)
            .padding(.bottom, 70)
            .frame(minHeight: 840, alignment: .bottom)
            .background {
                LinearGradient(
                    colors: [
                        .clear,
                        Color.black.opacity(0.28),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }

        private var centeredLogo: some View {
            ImageView(viewModel.item.imageSource(.logo, maxHeight: 120))
                .placeholder { _ in
                    EmptyView()
                }
                .failure {
                    Text(viewModel.item.displayTitle)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .opacity(choreography.centeredLogoOpacity)
                .offset(y: choreography.centeredLogoParallaxOffset)
        }

        private var seasonPills: some View {
            HStack(spacing: 18) {
                ForEach(Array(seasonTitles.enumerated()), id: \.offset) { index, title in
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(index == 0 ? Color.black : Color.white.opacity(0.95))
                        .padding(.vertical, 14)
                        .padding(.horizontal, 30)
                        .background(index == 0 ? Color.white : Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(choreography.seasonPillOpacity)
            .offset(y: choreography.seasonPillOffset)
        }

        private var episodePlaceholderRail: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: EdgeInsets.edgePadding / 2) {
                    ForEach(0 ..< 8, id: \.self) { index in
                        Button {} label: {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.18),
                                            Color.white.opacity(0.08),
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                )
                                .overlay(alignment: .bottomLeading) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(L10n.episodeNumber(index + 1))
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                        Text(L10n.episodes)
                                            .font(.callout)
                                            .foregroundStyle(.white.opacity(0.72))
                                    }
                                    .padding(20)
                                }
                                .frame(width: 430, height: 248)
                        }
                        .buttonStyle(.card)
                        .focused($focusedPlaceholderID, equals: "placeholder-\(index)")
                    }
                }
                .padding(.horizontal, EdgeInsets.edgePadding)
                .padding(.vertical, 8)
            }
            .frame(height: 285)
        }

        private var episodeSection: some View {
            Group {
                if showsLegacyEpisodeSelector, viewModel.seasons.isNotEmpty {
                    SeriesEpisodeSelector(viewModel: viewModel)
                } else {
                    episodePlaceholderRail
                }
            }
            .seriesEpisodeRailAnchor()
            .focusGuide(
                focusGuide,
                tag: "seriesEpisodes",
                onContentFocus: {
                    focusedPlaceholderID = focusedPlaceholderID ?? "placeholder-0"
                },
                top: "seriesHero"
            )
        }

        private var lowerPlaceholders: some View {
            VStack(spacing: 34) {
                placeholderSection(title: "Cast and Crew Placeholder", rows: 2)
                placeholderSection(title: "Synopsis Placeholder", rows: 3)
            }
            .offset(y: choreography.lowerContentDelayedOffset)
        }

        private func placeholderSection(title: String, rows: Int) -> some View {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                VStack(spacing: 10) {
                    ForEach(0 ..< rows, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(index == 0 ? 0.15 : 0.09))
                            .frame(height: 32)
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }

        var body: some View {
            VStack(spacing: 0) {
                heroSection

                VStack(spacing: 34) {
                    centeredLogo
                    seasonPills
                    episodeSection
                    lowerPlaceholders
                }
                .padding(.bottom, 90)
            }
            .background {
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.58),
                        Color.black.opacity(0.72),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}
