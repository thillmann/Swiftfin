//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import Logging
import SwiftUI

extension ItemView {

    struct PlayButton: View {

        private static let playAgainTitle = "Play Again"

        @Environment(\.isFocused)
        private var isFocused

        @Router
        private var router

        @ObservedObject
        var viewModel: ItemViewModel

        let showsProgressBar: Bool

        private let logger = Logger.swiftfin()

        init(
            viewModel: ItemViewModel,
            showsProgressBar: Bool = false
        ) {
            self.viewModel = viewModel
            self.showsProgressBar = showsProgressBar
        }

        // MARK: - Media Sources

        private var mediaSources: [MediaSourceInfo] {
            viewModel.playButtonItem?.mediaSources ?? []
        }

        // MARK: - Multiple Media Sources

        private var multipleVersions: Bool {
            mediaSources.count > 1
        }

        // MARK: - Validation

        private var isEnabled: Bool {
            viewModel.selectedMediaSource != nil
        }

        // MARK: - Title

        private var isPlayed: Bool {
            viewModel.playButtonItem?.userData?.isPlayed ?? false
        }

        private var playbackPositionTicks: Int {
            viewModel.playButtonItem?.userData?.playbackPositionTicks ?? 0
        }

        private var isPartiallyWatched: Bool {
            playbackPositionTicks > 0 && !isPlayed
        }

        private var seasonEpisodeLabel: String? {
            guard let playButtonItem = viewModel.playButtonItem else { return nil }

            if let seasonNumber = playButtonItem.parentIndexNumber,
               let episodeNumber = playButtonItem.indexNumber
            {
                return "S\(seasonNumber), E\(episodeNumber)"
            }

            return playButtonItem.seasonEpisodeLabel
        }

        private var title: String {
            if viewModel.playButtonItem?.isUnaired == true {
                return L10n.unaired
            }

            if viewModel.playButtonItem?.isMissing == true {
                return L10n.missing
            }

            if isPlayed {
                return Self.playAgainTitle
            }

            let actionLabel = isPartiallyWatched ? L10n.resume : L10n.play

            if let seasonEpisodeLabel {
                return "\(actionLabel) \(seasonEpisodeLabel)"
            }

            return actionLabel
        }

        // MARK: - Media Source

        private var source: String? {
            guard let sourceLabel = viewModel.selectedMediaSource?.displayTitle,
                  viewModel.playButtonItem?.mediaSources?.count ?? 0 > 1
            else {
                return nil
            }

            return sourceLabel
        }

        // MARK: - Progress

        private var progress: Double {
            let value = (viewModel.playButtonItem?.userData?.playedPercentage ?? 0) / 100
            return min(max(value, 0), 1)
        }

        private var remainingDuration: String? {
            guard let playButtonItem = viewModel.playButtonItem else { return nil }

            guard let runTimeTicks = playButtonItem.runTimeTicks else {
                return playButtonItem.runTimeLabel
            }

            let remainingTicks = max(0, runTimeTicks - playbackPositionTicks)
            return Duration.ticks(remainingTicks).formatted(.hourMinuteAbbreviated)
        }

        // MARK: - Body

        var body: some View {
            HStack(spacing: 30) {
                playButton

                if multipleVersions {
                    VersionMenu(viewModel: viewModel, mediaSources: mediaSources)
                        .frame(width: 100, height: 100)
                }
            }
            .fontWeight(.semibold)
        }

        // MARK: - Play Button

        private var playButton: some View {
            Button {
                play()
            } label: {
                if showsProgressBar {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .semibold))

                        ProgressView(value: progress)
                            .progressViewStyle(
                                FeatureInlineProgressStyle(
                                    trackColor: isFocused ? .black.opacity(0.2) : .white.opacity(0.2),
                                    fillColor: isFocused ? .black : .white
                                )
                            )
                            .frame(width: 90)

                        Text(remainingDuration ?? .emptyDash)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 40)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")

                        VStack {
                            Text(title)

                            if let source {
                                Marquee(source, animateWhenFocused: true)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                }
            }
            .buttonStyle(
                .featureButton
            )
            .contextMenu {
                if viewModel.playButtonItem?.userData?.playbackPositionTicks != 0 {
                    Button(L10n.playFromBeginning, systemImage: "gobackward") {
                        play(fromBeginning: true)
                    }
                }
            }
            .isSelected(true)
            .enabled(isEnabled)
        }

        // MARK: - Play Content

        private func play(fromBeginning: Bool = false) {
            guard let playButtonItem = viewModel.playButtonItem,
                  let selectedMediaSource = viewModel.selectedMediaSource
            else {
                logger.error("Play selected with no item or media source")
                return
            }

            let queue: (any MediaPlayerQueue)? = {
                if playButtonItem.type == .episode {
                    return EpisodeMediaPlayerQueue(episode: playButtonItem)
                }
                return nil
            }()

            let provider = MediaPlayerItemProvider(item: playButtonItem) { item in
                try await MediaPlayerItem.build(
                    for: item,
                    mediaSource: selectedMediaSource
                ) {
                    if fromBeginning {
                        $0.userData?.playbackPositionTicks = 0
                    }
                }
            }

            router.route(
                to: .videoPlayer(
                    provider: provider,
                    queue: queue
                )
            )
        }
    }
}
