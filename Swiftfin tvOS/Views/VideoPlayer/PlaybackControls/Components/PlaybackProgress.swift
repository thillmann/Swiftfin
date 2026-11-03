//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

// TODO: enabled/disabled state
// TODO: scrubbing snapping behaviors
//       - chapter boundaries
//       - current running time
// TODO: show chapter title under preview image
//       - have max width, on separate offset track

extension VideoPlayer.PlaybackControls {

    struct PlaybackProgress: View {

        @Default(.VideoPlayer.Overlay.chapterSlider)
        private var chapterSlider

        @Environment(ViewState.self)
        private var viewState
        @Environment(MediaSession.self)
        private var mediaSession
        @State
        private var sliderSize: CGSize = .zero

        @Toaster
        private var toaster: ToastProxy

        private let previewImageHeight: CGFloat = 200

        private var sliderHeight: CGFloat {
            isScrubbing ? 20 : 14
        }

        private var isScrubbing: Bool {
            viewState.isScrubbing
        }

        private var scrubbedProgress: Double {
            guard let runtime = mediaSession.item.runtime, runtime > .zero else { return 0 }

            let progress = viewState.scrubbedSeconds / runtime
            guard progress.isFinite else { return 0 }

            return clamp(progress, min: 0, max: 1)
        }

        private var currentProgress: Double? {
            guard isScrubbing,
                  let runtime = mediaSession.item.runtime,
                  runtime > .zero
            else {
                return nil
            }

            let currentSeconds = viewState.scrubOriginSeconds ?? mediaSession.seconds
            let progress = (currentSeconds / runtime) * 100
            guard progress.isFinite else { return nil }

            return clamp(progress, min: 0, max: 100)
        }

        private var videoSizeAspectRatio: CGFloat {
            guard let aspectRatio = (mediaSession.player as? any VideoMediaPlayer)?
                .videoState
                .videoSize
                .aspectRatio
            else {
                return 1.77
            }

            return clamp(aspectRatio, min: 0.25, max: 4)
        }

        private var previewXOffset: CGFloat {
            guard sliderSize.width.isFinite, sliderSize.width > 0 else { return 0 }

            let videoWidth = previewImageHeight * videoSizeAspectRatio
            let p = (sliderSize.width * scrubbedProgress) - (videoWidth / 2)

            return clamp(p, min: 0, max: max(0, sliderSize.width - videoWidth))
        }

        private var liveIndicator: some View {
            Text(L10n.live)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(Color.gray)
                }
        }

        private var videoPlayerSlider: some View {
            SliderContainer(
                value: Bindable(viewState).scrubbedSeconds.map(
                    getter: {
                        guard let runtime = mediaSession.item.runtime, runtime > .zero else { return 0 }

                        let seconds = $0.seconds
                        let runtimeSeconds = runtime.seconds
                        guard seconds.isFinite, runtimeSeconds.isFinite, runtimeSeconds > 0 else { return 0 }

                        return clamp((seconds / runtimeSeconds) * 100, min: 0, max: 100)
                    },
                    setter: {
                        guard $0.isFinite else { return .zero }

                        return (mediaSession.item.runtime ?? .zero) * (clamp($0, min: 0, max: 100) / 100)
                    }
                ),
                total: 100,
                isScrollingEnabled: mediaSession.playbackRequestStatus == .paused && mediaSession.canSeek,
                originProgress: currentProgress
            )
            .onEditingChanged { isEditing in
                if isEditing {
                    viewState.beginScrub()
                }
            }
            .sliderContainerStyle(.capsule(showsProgressWhenUnfocused: false))
            .if(chapterSlider) { view in
                if let chapters = mediaSession.item.chapters, chapters.isNotEmpty {
                    view.inverseMask { ChapterTrackMask(chapters: chapters, runtime: mediaSession.item.runtime ?? .zero) }
                } else {
                    view
                }
            }
            .frame(height: sliderHeight)
            .trackingSize($sliderSize)
            .foregroundStyle(mediaSession.canSeek ? Color.primary : Color.gray)
            // Stay focusable while loading so the player receives remote input from the start.
            // Scrubbing is gated on `canSeek` separately.
        }

        private var liveProgramDates: (start: Date, end: Date)? {
            guard mediaSession.item.isLiveStream,
                  mediaSession.intent.item.type == .program,
                  let start = mediaSession.intent.item.startDate,
                  let end = mediaSession.intent.item.endDate,
                  end > start
            else {
                return nil
            }

            return (start, end)
        }

        private func liveProgramProgress(at date: Date, start: Date, end: Date) -> Double {
            let duration = end.timeIntervalSince(start)
            let elapsed = date.timeIntervalSince(start)
            return clamp((elapsed / duration) * 100, min: 0, max: 100)
        }

        @ViewBuilder
        private var liveProgramProgress: some View {
            if let liveProgramDates {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 10) {
                        SliderContainer(
                            value: .constant(
                                liveProgramProgress(
                                    at: context.date,
                                    start: liveProgramDates.start,
                                    end: liveProgramDates.end
                                )
                            ),
                            total: 100,
                            isScrollingEnabled: false,
                            originProgress: nil
                        )
                        .sliderContainerStyle(.capsule(showsProgressWhenUnfocused: true))
                        .disabled(true)
                        .frame(height: sliderHeight)

                        HStack {
                            Text(liveProgramDates.start, format: .dateTime.hour().minute())

                            Spacer()

                            Text(liveProgramDates.end, format: .dateTime.hour().minute())
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                    }
                }
            } else {
                liveIndicator
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        @ViewBuilder
        private var previewImage: some View {
            if isScrubbing, let previewImageProvider = mediaSession.playbackItem?.previewImageProvider {
                PreviewImageView(previewImageProvider: previewImageProvider)
                    .aspectRatio(videoSizeAspectRatio, contentMode: .fit)
                    .frame(height: previewImageHeight)
                    .posterBorder()
                    .cornerRadius(ratio: 1 / 30, of: \.width)
                    .offset(x: previewXOffset, y: -(previewImageHeight + 10))
                    .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 4)
            }
        }

        var body: some View {
            VStack(spacing: 10) {
                if mediaSession.item.isLiveStream {
                    liveProgramProgress
                } else {
                    videoPlayerSlider

                    SplitTimeStamp()
                        .foregroundStyle(.white, Color.lightGray)
                }
            }
            .coordinatedFocus(ViewState.Focus.progress)
            .foregroundStyle(Color.white.opacity(0.75))
            .overlay(alignment: .topLeading) {
                previewImage
            }
        }
    }
}
