//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import Logging
import SwiftUI

extension PlatformItemView {

    /// The playback action shared by the iOS and tvOS item heroes.
    struct PlayButton: View {

        @Router
        private var router

        #if os(iOS)
        @ObservedObject
        private var downloadManager = Container.shared.downloadManager()
        #endif

        @ObservedObject
        var viewModel: ItemViewModel

        @State
        private var isPreparingPlayback = false
        @State
        private var isMediaSourceSelectorPresented = false
        @State
        private var mediaSourceSelectorPresentationID = UUID()

        let showsProgressBar: Bool

        private let logger = Logger.swiftfin()

        init(viewModel: ItemViewModel, showsProgressBar: Bool = true) {
            self.viewModel = viewModel
            self.showsProgressBar = showsProgressBar
        }

        private var isEnabled: Bool {
            viewModel.playButtonItem != nil
        }

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

            if !usesProgressBar, let seasonEpisodeLabel {
                return "\(actionLabel) \(seasonEpisodeLabel)"
            }

            return actionLabel
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

        private var usesProgressBar: Bool {
            showsProgressBar && isPartiallyWatched && remainingDuration != nil
        }

        private var progress: Double {
            let value = (viewModel.playButtonItem?.userData?.playedPercentage ?? 0) / 100
            return min(max(value, 0), 1)
        }

        var body: some View {
            playButton
                .fontWeight(.semibold)
                .sheet(isPresented: $isMediaSourceSelectorPresented) {
                    MediaSourceSelector(viewModel: viewModel)
                        .id(mediaSourceSelectorPresentationID)
                    #if os(iOS)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.hidden)
                    #endif
                }
        }

        private var playButton: some View {
            Button {
                play()
            } label: {
                HStack(spacing: 12) {
                    if isPreparingPlayback {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.black)
                        Text(title)
                    } else if usesProgressBar {
                        Image(systemName: "play.fill")

                        ProgressView(value: progress)
                            .progressViewStyle(
                                FeatureInlineProgressStyle(
                                    trackColor: .black.opacity(0.2),
                                    fillColor: .black
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
                .padding(.horizontal, FeatureButtonTokens.horizontalPadding)
            }
            .buttonStyle(.featureButton)
            .contextMenu {
                if viewModel.playButtonItem?.userData?.playbackPositionTicks != 0 {
                    Button(L10n.playFromBeginning, systemImage: "gobackward") {
                        play(fromBeginning: true)
                    }
                }

                if isEnabled,
                   !viewModel.isOffline,
                   PlatformItemView.shouldPresentMediaSourceSelector(for: viewModel)
                {
                    Button(L10n.version, systemImage: "list.triangle") {
                        mediaSourceSelectorPresentationID = UUID()
                        isMediaSourceSelectorPresented = true
                    }
                }
            }
            .isSelected(true)
            .enabled(isEnabled && !isPreparingPlayback)
        }

        private func play(fromBeginning: Bool = false) {
            guard !isPreparingPlayback else { return }

            isPreparingPlayback = true
            Task { @MainActor in
                defer { isPreparingPlayback = false }
                let preferredLocalRecord: DownloadRecord?
                #if os(iOS)
                preferredLocalRecord = viewModel.offlineRecord ?? viewModel.playButtonItem.flatMap {
                    downloadManager.completedRecord(for: $0, mediaSource: nil)
                }
                #else
                preferredLocalRecord = viewModel.offlineRecord
                #endif

                if preferredLocalRecord == nil,
                   !viewModel.isOffline,
                   case .automatic = viewModel.mediaSourceSelectionIntent
                {
                    await viewModel.waitForMediaSourceCatalogue()
                }
                startPlayback(
                    fromBeginning: fromBeginning,
                    preferredLocalRecord: preferredLocalRecord
                )
            }
        }

        @MainActor
        private func startPlayback(
            fromBeginning: Bool,
            preferredLocalRecord: DownloadRecord?
        ) {
            guard let playButtonItem = viewModel.playButtonItem else {
                logger.error("Play selected with no item")
                return
            }

            let selectedMediaSource = viewModel.playbackMediaSource
            if case .automatic = viewModel.mediaSourceSelectionIntent,
               preferredLocalRecord == nil,
               selectedMediaSource == nil
            {
                logger.error("Automatic playback found no source matching the requested media")
                viewModel.presentAutomaticMediaSourceError()
                return
            }
            #if os(iOS)
            let localRecord = preferredLocalRecord
                ?? viewModel.offlineRecord
                ?? downloadManager.completedRecord(
                    for: playButtonItem,
                    mediaSource: selectedMediaSource
                )
            #else
            let localRecord = preferredLocalRecord ?? viewModel.offlineRecord
            #endif

            let queue: (any MediaPlayerQueue)? = {
                // The online episode queue may fetch adjacent episodes. Keep
                // exact-version offline playback local and isolated for now.
                if localRecord != nil { return nil }
                if playButtonItem.type == .episode {
                    return EpisodeMediaPlayerQueue(episode: playButtonItem)
                }
                return nil
            }()

            let provider = MediaPlayerItemProvider(item: playButtonItem, offlineRecord: localRecord) { item in
                if let localRecord {
                    var record = localRecord
                    if fromBeginning {
                        record.offlineProgress = .init(
                            positionTicks: 0,
                            isPlayed: false,
                            updatedAt: .now
                        )
                    }
                    return try await MediaPlayerItem.buildOffline(record: record)
                }

                return try await MediaPlayerItem.build(
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
