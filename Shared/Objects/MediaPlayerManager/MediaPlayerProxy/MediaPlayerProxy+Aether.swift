//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AetherEngine
import AVFoundation
import Combine
import Defaults
import Foundation
@preconcurrency import JellyfinAPI
import SwiftUI

#if os(iOS)
import AVKit
import CoreMedia
#endif

/// Experimental AetherEngine adapter. It intentionally lives beside the VLC
/// and AVPlayer proxies so the backend can be evaluated without replacing
/// either established playback path.
@MainActor
final class AetherMediaPlayerProxy: VideoMediaPlayerLayoutConfigurable {

    let isBuffering: PublishedBox<Bool> = .init(initialValue: false)
    let videoSize: PublishedBox<CGSize> = .init(initialValue: .zero)
    let droppedFrames: PublishedBox<Int> = .init(initialValue: 0)
    let corruptedFrames: PublishedBox<Int> = .init(initialValue: 0)

    let engine: AetherEngine

    private var engineCancellables: Set<AnyCancellable> = []
    private var managerCancellables: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?
    private var desiredPlaybackRate: Float = Float(Defaults[.VideoPlayer.Playback.playbackRate])

    #if os(iOS)
    private lazy var pictureInPictureCoordinator = AetherPictureInPictureCoordinator(engine: engine)
    #endif

    weak var manager: MediaPlayerManager? {
        didSet {
            managerCancellables.removeAll()

            for var observer in observers {
                observer.manager = manager
            }

            guard let manager else { return }

            manager.$playbackItem
                .compactMap(\.self)
                .sink { [weak self] item in
                    self?.playNew(item: item)
                }
                .store(in: &managerCancellables)

            manager.$state
                .sink { [weak self] state in
                    if state == .stopped {
                        self?.stop()
                    }
                }
                .store(in: &managerCancellables)

            manager.$rate
                .removeDuplicates()
                .sink { [weak self] rate in
                    self?.setRate(rate)
                }
                .store(in: &managerCancellables)
        }
    }

    var observers: [any MediaPlayerObserver] = [
        NowPlayableObserver(),
    ]

    init() {
        do {
            self.engine = try AetherEngine()
        } catch {
            fatalError("Unable to initialize AetherEngine: \(error)")
        }

        bindEngineState()

        #if os(iOS)
        _ = pictureInPictureCoordinator
        #endif
    }

    func play() {
        engine.play()
        engine.setRate(desiredPlaybackRate)
    }

    func pause() {
        engine.pause()
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        engine.stop()
    }

    func jumpForward(_ seconds: Duration) {
        let requestedTarget = engine.currentTime + seconds.seconds
        let target = engine.duration > 0 ? min(requestedTarget, engine.duration) : requestedTarget
        seek(to: target)
    }

    func jumpBackward(_ seconds: Duration) {
        seek(to: max(0, engine.currentTime - seconds.seconds))
    }

    func setRate(_ rate: Double) {
        desiredPlaybackRate = Float(rate)

        guard engine.state == .playing else { return }

        engine.setRate(Float(rate))
    }

    func setSeconds(_ seconds: Duration) {
        seek(to: seconds.seconds)
    }

    func setAudioStream(_ stream: MediaStream) {
        guard let index = stream.index, index >= 0 else { return }

        engine.selectAudioTrack(index: index)
    }

    func setSubtitleStream(_ stream: MediaStream) {
        guard let playerIndex = stream.index, playerIndex >= 0 else {
            engine.clearSubtitle()
            return
        }

        engine.selectSubtitleTrack(index: playerIndex)
    }

    func setAspectFill(_ aspectFill: Bool) {
        engine.videoGravity = aspectFill ? .resizeAspectFill : .resizeAspect
    }

    func videoPlayerBody(layout: VideoPlayer.VideoLayout) -> some View {
        AetherPlayerView(engine: engine, layout: layout)
            .onAppear { self.engine.videoGravity = .resizeAspect }
    }
}

private extension AetherMediaPlayerProxy {

    func bindEngineState() {
        engine.$isBuffering
            .removeDuplicates()
            .sink { [weak self] isBuffering in
                self?.isBuffering.value = isBuffering
            }
            .store(in: &engineCancellables)

        engine.$state
            .removeDuplicates()
            .sink { [weak self] state in
                self?.handle(state: state)
            }
            .store(in: &engineCancellables)

        // Swiftfin fans `manager.seconds` out to the playback UI, chapter
        // tracking, and MPNowPlayingInfoCenter. Updating all of those at
        // Aether's transport-clock cadence can monopolize the main actor
        // and starve the software playback path.
        engine.clock
            .$currentTime
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] seconds in
                guard seconds.isFinite else { return }

                self?.manager?.seconds = .seconds(seconds)
            }
            .store(in: &engineCancellables)
    }

    func handle(state: PlaybackState) {
        switch state {
        case .idle:
            isBuffering.value = false

        case .loading, .seeking:
            isBuffering.value = true

        case .playing:
            isBuffering.value = false
            engine.setRate(desiredPlaybackRate)

        case .paused:
            isBuffering.value = false

        case .ended:
            isBuffering.value = false
            guard manager?.playbackItem?.baseItem.isLiveStream == false else { return }

            Task { await manager?.ended() }

        case let .error(message):
            isBuffering.value = false
            Task { await manager?.error(ErrorMessage("AetherEngine playback failed: \(message)")) }
        }
    }

    func playNew(item: MediaPlayerItem) {
        loadTask?.cancel()

        let sidecars: [(stream: MediaStream, track: ExternalSubtitleTrack)] = item.subtitleStreams.sidecarSubtitles.compactMap { stream in
            guard let url = stream.resolvedDeliveryURL else { return nil }

            return (
                stream,
                ExternalSubtitleTrack(
                    url: url,
                    name: stream.displayTitle,
                    language: stream.language,
                    isForced: stream.isForced ?? false,
                    isDefault: stream.isDefault ?? false,
                    formatHint: stream.codec
                )
            )
        }

        let startSeconds = max(
            0,
            (item.baseItem.startSeconds ?? .zero).seconds - Double(Defaults[.VideoPlayer.resumeOffset])
        )
        let initialAudioIndex: Int32? = {
            guard let index = item.selectedAudioStreamIndex, index >= 0 else { return nil }

            if item.mediaSource.transcodingURL != nil { return 1 }
            let externalCount = item.mediaSource.mediaStreams?.count(where: { $0.isExternal == true }) ?? 0
            return Int32(max(0, index - externalCount))
        }()
        let options = LoadOptions(
            isLive: item.baseItem.isLiveStream,
            nativeRemoteHLS: item.baseItem.isLiveStream && item.mediaSource.transcodingURL != nil,
            externalSubtitles: sidecars.map(\.track),
            autoplay: false
        )

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                engine.setExternalMetadata(item.baseItem.avMetadata)

                let probe = try await engine.load(
                    url: item.url,
                    startPosition: startSeconds,
                    options: options,
                    audioSourceStreamIndex: initialAudioIndex
                )
                try Task.checkCancellation()

                if let probe, probe.videoWidth > 0, probe.videoHeight > 0 {
                    videoSize.value = CGSize(width: Int(probe.videoWidth), height: Int(probe.videoHeight))
                }

                var trackMap = MediaTrackIndexMap()
                let embeddedAudio = item.audioStreams.filter { $0.isExternal != true }
                if item.mediaSource.transcodingURL != nil {
                    if let selected = item.selectedAudioStreamIndex, let track = engine.audioTracks.first {
                        trackMap.setPlayerIndex(track.id, for: selected)
                    }
                } else {
                    for (stream, track) in zip(embeddedAudio, engine.audioTracks) {
                        if let index = stream.index { trackMap.setPlayerIndex(track.id, for: index) }
                    }
                }
                let embeddedSubtitles = item.subtitleStreams.filter { $0.isExternal != true && $0.deliveryMethod != .encode }
                for (stream, track) in zip(embeddedSubtitles, engine.subtitleTracks.filter { !$0.isExternal }) {
                    if let index = stream.index { trackMap.setPlayerIndex(track.id, for: index) }
                }
                for (entry, track) in zip(sidecars, engine.subtitleTracks.filter(\.isExternal)) {
                    if let index = entry.stream.index { trackMap.setPlayerIndex(track.id, for: index) }
                }
                item.setTrackIndexes(trackMap)

                if manager?.playbackRequestStatus == .playing {
                    play()
                } else {
                    pause()
                }
            } catch is CancellationError {
                // A newer item or an explicit stop superseded this load.
            } catch {
                await manager?.error(ErrorMessage("AetherEngine failed to load media: \(error.localizedDescription)"))
            }
        }
    }

    func seek(to seconds: Double) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            await engine.seek(to: max(0, seconds))
        }
    }
}

extension AetherMediaPlayerProxy {

    private struct AetherPlayerView: View {

        @Environment(VideoPlayer.ViewState.self)
        private var viewState

        let engine: AetherEngine
        let layout: VideoPlayer.VideoLayout

        var body: some View {
            ZStack {
                Color.black
                AetherPlayerSurface(engine: engine)
                    .frame(width: layout.renderSize.width, height: layout.renderSize.height)
                    .scaleEffect(layout.renderScale)
                    .offset(layout.renderOffset)
                AetherSubtitleOverlay(engine: engine)
            }
            .onReceive(
                engine.clock
                    .$currentTime
                    .throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)
            ) { seconds in
                if !viewState.isScrubbing {
                    viewState.scrubbedSeconds.value = .seconds(seconds)
                }
            }
        }
    }

    /// Keeps clock-driven subtitle invalidation below the player surface in
    /// the SwiftUI tree. Otherwise every clock tick calls updateUIView on the
    /// render surface while the software decoder is also trying to present.
    private struct AetherSubtitleOverlay: View {

        @Default(.VideoPlayer.Subtitle.configuration)
        private var subtitleConfiguration

        let engine: AetherEngine

        @State
        private var currentTime: Double = 0
        @State
        private var subtitleCues: [SubtitleCue] = []

        private var activeSubtitleCues: [SubtitleCue] {
            subtitleCues.filter { $0.startTime <= currentTime && currentTime < $0.endTime }
        }

        var body: some View {
            ZStack {
                subtitleOverlay
            }
            .allowsHitTesting(false)
            .onReceive(
                engine.clock
                    .$currentTime
                    .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            ) { seconds in
                guard subtitleCues.isNotEmpty else { return }

                currentTime = seconds
            }
            .onReceive(engine.$subtitleCues) { cues in
                subtitleCues = cues
            }
        }

        @ViewBuilder
        private var subtitleOverlay: some View {
            ForEach(activeSubtitleCues) { cue in
                switch cue.body {
                case let .text(text):
                    subtitleText(text)
                case let .richText(runs):
                    subtitleText(runs.map(\.text).joined())
                case let .image(image):
                    bitmapSubtitle(image)
                }
            }
        }

        private func subtitleText(_ text: String) -> some View {
            Text(text)
                .font(.custom(subtitleConfiguration.fontName, size: CGFloat(max(14, 25 - subtitleConfiguration.size))))
                .multilineTextAlignment(.center)
                .foregroundStyle(subtitleConfiguration.color)
                .shadow(color: .black, radius: 2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 30)
                .padding(.bottom, 70)
        }

        private func bitmapSubtitle(_ subtitle: SubtitleImage) -> some View {
            GeometryReader { geometry in
                let position = subtitle.position
                let width = max(1, position.width * geometry.size.width)
                let height = max(1, position.height * geometry.size.height)

                Image(uiImage: UIImage(cgImage: subtitle.cgImage))
                    .resizable()
                    .frame(width: width, height: height)
                    .position(
                        x: position.midX * geometry.size.width,
                        y: position.midY * geometry.size.height
                    )
            }
        }
    }
}

#if os(iOS)

@MainActor
private final class AetherPictureInPictureCoordinator: NSObject,
    AVPictureInPictureControllerDelegate,
    AVPictureInPictureSampleBufferPlaybackDelegate
{

    private weak var engine: AetherEngine?
    let isActive: PublishedBox<Bool> = .init(initialValue: false)
    let isAvailable: PublishedBox<Bool> = .init(initialValue: false)
    private var availabilityObservation: NSKeyValueObservation?

    func start() {
        controller?.startPictureInPicture()
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    private var controller: AVPictureInPictureController?
    private var softwareSource: SoftwarePiPSource?
    private var sourceIdentity: ObjectIdentifier?
    private var cancellables: Set<AnyCancellable> = []

    init(engine: AetherEngine) {
        self.engine = engine
        super.init()

        engine.$currentAVPlayer
            .combineLatest(engine.$softwarePiPSource)
            .sink { [weak self] _, softwareSource in
                self?.configureController(softwareSource: softwareSource)
            }
            .store(in: &cancellables)

        engine.$state
            .sink { [weak self] _ in
                self?.controller?.invalidatePlaybackState()
            }
            .store(in: &cancellables)
    }

    private func configureController(softwareSource: SoftwarePiPSource?) {
        guard AVPictureInPictureController.isPictureInPictureSupported(), let engine else { return }

        let contentSource: AVPictureInPictureController.ContentSource
        let identity: ObjectIdentifier

        if let softwareSource {
            self.softwareSource = softwareSource
            identity = ObjectIdentifier(softwareSource.layer)
            contentSource = .init(
                sampleBufferDisplayLayer: softwareSource.layer,
                playbackDelegate: self
            )
        } else if let playerLayer = engine.nativePlayerLayer {
            self.softwareSource = nil
            identity = ObjectIdentifier(playerLayer)
            contentSource = .init(playerLayer: playerLayer)
        } else {
            if controller?.isPictureInPictureActive != true {
                controller = nil
                sourceIdentity = nil
                isAvailable.value = false
                availabilityObservation = nil
            }
            return
        }

        guard sourceIdentity != identity else { return }

        sourceIdentity = identity

        if let controller, controller.isPictureInPictureActive {
            controller.contentSource = contentSource
        } else {
            let controller = AVPictureInPictureController(contentSource: contentSource)
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            self.controller = controller
            availabilityObservation = controller.observe(\.isPictureInPicturePossible, options: [
                .initial,
                .new
            ]) { [weak self] controller, _ in
                Task { @MainActor in self?.isAvailable.value = controller.isPictureInPicturePossible }
            }
        }
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive.value = true
        engine?.pictureInPictureActive = true
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive.value = false
        engine?.pictureInPictureActive = false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        isActive.value = false
        engine?.pictureInPictureActive = false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        softwareSource?.setPlaying(playing)
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        softwareSource?.timeRange() ?? .invalid
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        softwareSource?.isPaused ?? true
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        softwareSource?.skip(by: skipInterval.seconds)
        completionHandler()
    }
}

#endif

#if os(iOS)
extension AetherMediaPlayerProxy: MediaPlayerPictureInPictureCapable {
    var isPiPActive: PublishedBox<Bool> {
        pictureInPictureCoordinator.isActive
    }

    var isPiPAvailable: PublishedBox<Bool> {
        pictureInPictureCoordinator.isAvailable
    }

    func startPiP() {
        pictureInPictureCoordinator.start()
    }

    func stopPiP() {
        pictureInPictureCoordinator.stop()
    }
}
#endif
