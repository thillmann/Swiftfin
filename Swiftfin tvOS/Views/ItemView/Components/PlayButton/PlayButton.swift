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

        @FocusState
        private var isPlayButtonFocused: Bool

        @Router
        private var router

        @ObservedObject
        var viewModel: ItemViewModel

        let showsProgressBar: Bool
        let onMoveCommand: ((MoveCommandDirection) -> Void)?

        private let logger = Logger.swiftfin()

        init(
            viewModel: ItemViewModel,
            showsProgressBar: Bool = true,
            onMoveCommand: ((MoveCommandDirection) -> Void)? = nil
        ) {
            self.viewModel = viewModel
            self.showsProgressBar = showsProgressBar
            self.onMoveCommand = onMoveCommand
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
            viewModel.playButtonItem != nil
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

        private var usesProgressBar: Bool {
            showsProgressBar && isPartiallyWatched && remainingDuration != nil
        }

        private var progressTrackColor: Color {
            isPlayButtonFocused ? .black.opacity(0.2) : .white.opacity(0.2)
        }

        private var progressFillColor: Color {
            isPlayButtonFocused ? .black : .white
        }

        private var seasonEpisodeLabel: String? {
            guard let playButtonItem = viewModel.playButtonItem else { return nil }

            if let seasonNumber = playButtonItem.parentIndexNumber,
               let episodeNumber = playButtonItem.indexNumber
            {
                return L10n.seasonAndEpisode(String(seasonNumber), String(episodeNumber))
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
                return L10n.playAgain
            }

            if isPartiallyWatched, remainingDuration == nil {
                return L10n.resume
            }

            let actionLabel = isPartiallyWatched ? L10n.resume : L10n.play

            if let seasonEpisodeLabel {
                return "\(actionLabel) \(seasonEpisodeLabel)"
            }

            return actionLabel
        }

        // MARK: - Progress

        private var progress: Double {
            let value = (viewModel.playButtonItem?.userData?.playedPercentage ?? 0) / 100
            return min(max(value, 0), 1)
        }

        private var remainingDuration: String? {
            guard let playButtonItem = viewModel.playButtonItem else { return nil }

            let duration: String?
            if let runTimeTicks = playButtonItem.runTimeTicks {
                let remainingTicks = max(0, runTimeTicks - playbackPositionTicks)
                duration = Duration.ticks(remainingTicks).formatted(.hourMinuteAbbreviated)
            } else {
                duration = playButtonItem.runTimeLabel
            }

            return duration?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }

        // MARK: - Body

        var body: some View {
            HStack(spacing: FeatureButtonTokens.actionSpacing) {
                playButton

                if multipleVersions {
                    MediaSourceMenu(viewModel: viewModel, mediaSources: mediaSources)
                }
            }
            .fontWeight(.semibold)
        }

        // MARK: - Play Button

        private var playButton: some View {
            let button = Button {
                play()
            } label: {
                HStack(spacing: 12) {
                    if usesProgressBar {
                        Image(systemName: "play.fill")

                        ProgressView(value: progress)
                            .progressViewStyle(
                                FeatureInlineProgressStyle(
                                    trackColor: progressTrackColor,
                                    fillColor: progressFillColor
                                )
                            )
                            .frame(width: 40)

                        Text(remainingDuration ?? .emptyDash)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "play.fill")

                        Text(title)
                    }
                }
                .font(FeatureButtonTokens.labelFont)
                .padding(.horizontal, 40)
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
            .focused($isPlayButtonFocused)

            return Group {
                if let onMoveCommand {
                    button.onMoveCommand(perform: onMoveCommand)
                } else {
                    button
                }
            }
        }

        // MARK: - Play Content

        private func play(fromBeginning: Bool = false) {
            guard let playButtonItem = viewModel.playButtonItem else {
                logger.error("Play selected with no item")
                return
            }

            let selectedMediaSource = viewModel.selectedMediaSource

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
