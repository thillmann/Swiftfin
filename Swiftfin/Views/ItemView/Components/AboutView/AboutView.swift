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

    struct AboutView: View {

        private struct Detail: Identifiable {
            let label: String
            let value: String

            var id: String {
                label
            }
        }

        @Router
        private var router

        @ObservedObject
        var viewModel: ItemViewModel

        private var information: [Detail] {
            var details: [Detail] = []

            if let releaseYear = viewModel.item.premiereDateYear ?? viewModel.item.productionYear.map({ String($0) }) {
                details.append(.init(label: "Released", value: releaseYear))
            }

            if let officialRating = viewModel.item.officialRating, officialRating.isNotEmpty {
                details.append(.init(label: "Rated", value: officialRating))
            }

            let productionLocations = viewModel.item.productionLocations?
                .filter(\.isNotEmpty)
                .joined(separator: ", ") ?? ""
            if productionLocations.isNotEmpty {
                details.append(.init(label: "Regions of Origin", value: productionLocations))
            }

            return details
        }

        private var audioStreams: [MediaStream] {
            viewModel.selectedMediaSource?.audioStreams ?? []
        }

        private var originalAudio: String? {
            let stream = audioStreams.first(where: { $0.isDefault == true }) ?? audioStreams.first
            return stream?.language ?? stream?.displayTitle
        }

        private var audioTracks: [String] {
            audioStreams.reduce(into: []) { tracks, stream in
                guard let track = stream.displayTitle ?? stream.language,
                      track.isNotEmpty,
                      !tracks.contains(track)
                else { return }

                tracks.append(track)
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: PlatformItemView.detailSectionSpacing) {
                aboutSection

                if information.isNotEmpty {
                    detailSection(title: "Information", details: information)
                }

                if audioTracks.isNotEmpty {
                    languagesSection
                }
            }
            .id(viewModel.item.hashValue)
        }

        private var aboutSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle(L10n.about)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.item.displayTitle)
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)

                        if let genres = viewModel.item.itemGenres, genres.isNotEmpty {
                            Text(genres.map(\.displayTitle).joined(separator: ", "))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .lineLimit(2)
                        }
                    }

                    Group {
                        if let overview = viewModel.item.overview, overview.isNotEmpty {
                            TruncatedText(overview)
                                .onSeeMore {
                                    router.route(to: .itemOverview(item: viewModel.item))
                                }
                                .seeMoreType(.pill)
                                .lineLimit(4)
                        } else {
                            Text(L10n.noOverviewAvailable)
                        }
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(16)
                .background(Color.secondarySystemFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                    router.route(to: .itemOverview(item: viewModel.item))
                }
                .accessibility(addTraits: [.isButton])
                .edgePadding(.horizontal)
            }
        }

        private func detailSection(title: String, details: [Detail]) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(title)

                VStack(alignment: .leading, spacing: 24) {
                    ForEach(details) { detail in
                        detailRow(label: detail.label, value: detail.value)
                    }
                }
                .edgePadding(.horizontal)
            }
        }

        private var languagesSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Languages")

                VStack(alignment: .leading, spacing: 24) {
                    if let originalAudio {
                        detailRow(label: "Original Audio", value: originalAudio)
                    }

                    detailRow(label: L10n.audio, value: audioTracks.joined(separator: ", "))
                }
                .edgePadding(.horizontal)
            }
        }

        private func sectionTitle(_ title: String) -> some View {
            Text(title)
                .font(.title2.weight(.bold))
                .accessibility(addTraits: [.isHeader])
                .edgePadding(.horizontal)
        }

        private func detailRow(label: String, value: String) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.body)

                Text(value)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
