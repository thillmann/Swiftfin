//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension ItemView {

    struct AttributesHStack: View {

        let attributes: [ItemViewAttribute]
        @SharedBaseItem
        var item: BaseItemDto
        let selectedMediaSource: MediaSourceInfo?

        var alignment: HorizontalAlignment = .center
        var flowDirection: FlowLayout.Direction = .up

        var body: some View {
            if attributes.isNotEmpty {
                FlowLayout(
                    alignment: alignment,
                    direction: flowDirection,
                    spacing: UIDevice.isTV ? 20 : 8
                ) {
                    ForEach(attributes, id: \.self) { attribute in
                        switch attribute {
                        case .ratingCritics: CriticRating()
                        case .ratingCommunity: CommunityRating()
                        case .ratingOfficial: OfficialRating()
                        case .videoQuality: VideoQuality()
                        case .audioChannels: AudioChannels()
                        case .subtitles: Subtitles()
                        }
                    }
                }
                .lineLimit(1)
            }
        }

        @ViewBuilder
        private func CriticRating() -> some View {
            if let criticRating = item.criticRating {
                Label {
                    // swiftlint:disable:next hard_coded_display_string
                    Text("\(criticRating, specifier: "%.0f")")
                } icon: {
                    if criticRating >= 60 {
                        Image(.tomatoFresh)
                            .symbolRenderingMode(.hierarchical)
                    } else {
                        Image(.tomatoRotten)
                    }
                }
                .labelStyle(.attributeBadgeOutline)
            }
        }

        @ViewBuilder
        private func CommunityRating() -> some View {
            if let communityRating = item.communityRating {
                Label {
                    // swiftlint:disable:next hard_coded_display_string
                    Text("\(communityRating, specifier: "%.01f")")
                } icon: {
                    Image(systemName: "star.fill")
                }
                .labelStyle(.attributeBadgeOutline)
            }
        }

        @ViewBuilder
        private func OfficialRating() -> some View {
            if let officialRating = item.officialRating {
                EmptyLabel(officialRating)
                    .labelStyle(.attributeBadgeOutline)
            }
        }

        @ViewBuilder
        private func VideoQuality() -> some View {
            if let mediaStreams = selectedMediaSource?.mediaStreams {
                if mediaStreams.has4KVideo {
                    EmptyLabel("4K")
                        .labelStyle(.attributeBadgeFill)
                } else if mediaStreams.hasHDVideo {
                    EmptyLabel("HD")
                        .labelStyle(.attributeBadgeFill)
                }
                if mediaStreams.hasDolbyVision {
                    EmptyLabel("DV")
                        .labelStyle(.attributeBadgeFill)
                }
                if mediaStreams.hasHDRVideo {
                    EmptyLabel("HDR")
                        .labelStyle(.attributeBadgeFill)
                }
            }
        }

        @ViewBuilder
        private func AudioChannels() -> some View {
            if let mediaStreams = selectedMediaSource?.mediaStreams {
                if mediaStreams.has51AudioChannelLayout {
                    EmptyLabel("5.1")
                        .labelStyle(.attributeBadgeFill)
                }
                if mediaStreams.has71AudioChannelLayout {
                    EmptyLabel("7.1")
                        .labelStyle(.attributeBadgeFill)
                }
            }
        }

        @ViewBuilder
        private func Subtitles() -> some View {
            if let mediaStreams = selectedMediaSource?.mediaStreams,
               mediaStreams.hasSubtitles
            {
                EmptyLabel("CC")
                    .labelStyle(.attributeBadgeOutline)
            }
        }
    }
}

#if DEBUG
@MainActor
private func makeAttributeHStackPreviewViewModel() -> ItemViewModel {
    var item = BaseItemDto(
        id: "preview-item",
        name: "Preview Movie",
        type: .movie
    )
    item.criticRating = 86
    item.communityRating = 7.8
    item.officialRating = "PG-13"

    let mediaStreams: [MediaStream] = [
        .init(
            type: .video,
            videoRangeType: .doviWithHDR10,
            width: 3840
        ),
        .init(
            channelLayout: "7.1",
            type: .audio
        ),
        .init(type: .subtitle),
    ]
    let mediaSource = MediaSourceInfo(
        id: "preview-media-source",
        mediaStreams: mediaStreams
    )

    let viewModel = ItemViewModel(item: item)
    viewModel.send(.selectMediaSource(mediaSource))

    return viewModel
}

#Preview("Attributes", traits: .sizeThatFitsLayout) {
    ItemView.AttributesHStack(
        attributes: [
            .ratingCritics,
            .ratingCommunity,
            .ratingOfficial,
            .videoQuality,
            .audioChannels,
            .subtitles,
        ],
        viewModel: makeAttributeHStackPreviewViewModel(),
        alignment: .leading
    )
    .padding()
    .background(Color.black)
}
#endif
