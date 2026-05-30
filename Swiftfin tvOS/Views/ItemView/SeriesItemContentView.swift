//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ItemView {

    struct SeriesItemContentView: View {

        @EnvironmentObject
        private var focusGuide: FocusGuide

        @FocusState
        private var focusedPlaceholderID: String?
        @State
        private var showsHeroOverlay = false

        private let baseEpisodeTopPadding: CGFloat = -100
        private let focusedEpisodeExtraLift: CGFloat = 0

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
                        .focusSection()
                        .focusGuide(
                            focusGuide,
                            tag: "belowHeader",
                            onContentFocus: {
                                focusedPlaceholderID = focusedPlaceholderID ?? "placeholder-0"
                            },
                            top: "header"
                        )
                }
            }
        }

        private var animatedHeroOverlay: some View {
            VStack(spacing: 22) {
                centeredLogo
                seasonPills
            }
            .opacity(showsHeroOverlay ? 1 : 0)
            .offset(y: showsHeroOverlay ? 0 : 20)
            .animation(.easeOut(duration: 0.25), value: showsHeroOverlay)
            .padding(.top, 16)
            .allowsHitTesting(false)
        }

        private var lowerPlaceholders: some View {
            VStack(spacing: 34) {
                placeholderSection(title: "Cast and Crew Placeholder", rows: 2)
                placeholderSection(title: "Synopsis Placeholder", rows: 3)
            }
            .offset(y: showsHeroOverlay ? 0 : 28)
            .animation(.easeOut(duration: 0.25), value: showsHeroOverlay)
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
            VStack(spacing: 34) {
                ZStack(alignment: .top) {
                    episodeSection
                        .padding(
                            .top,
                            baseEpisodeTopPadding - (showsHeroOverlay ? focusedEpisodeExtraLift : 0)
                        )
                        .animation(.easeOut(duration: 0.25), value: showsHeroOverlay)

                    animatedHeroOverlay
                }
                lowerPlaceholders
            }
            .padding(.bottom, 90)
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
            .onAppear {
                updateHeroOverlayVisibility(for: focusGuide.focusedTag)
            }
            .onChange(of: focusGuide.focusedTag) { _, newTag in
                updateHeroOverlayVisibility(for: newTag)
            }
            .onMoveCommand { direction in
                guard direction == .up, showsHeroOverlay else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    focusGuide.transition(to: "header")
                }
            }
        }

        private func updateHeroOverlayVisibility(for focusedTag: String?) {
            let showsOverlayTags = ["belowHeader", "episodes"]
            showsHeroOverlay = showsOverlayTags.contains(focusedTag ?? "")
        }
    }
}
