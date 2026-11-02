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
import Foundation
@preconcurrency import JellyfinAPI
import MPVUI
import Observation
import SwiftUI

#if os(iOS)
import AVKit
import CoreMedia
#endif

// AetherEngine exports `PlaybackState` and `SubtitleCue`, which Swiftfin also declares.
// Engine values of those types are only used through inference below.

@MainActor
@Observable
final class AetherMediaPlayer: VideoMediaPlayer {

    let displayTitle = MediaPlayerType.aether.displayTitle
    let playbackProfile = PlaybackProfile.local(.aether)
    private(set) var videoState = VideoPlaybackState()

    @ObservationIgnored
    let engine: AetherEngine

    @ObservationIgnored
    weak var mediaSession: MediaSession?

    @ObservationIgnored
    private var desiredRate: Float = 1
    @ObservationIgnored
    private var engineCancellables: Set<AnyCancellable> = []
    @ObservationIgnored
    private var isReady = false
    @ObservationIgnored
    private var loadedItem: MediaPlayerItem?
    @ObservationIgnored
    private var loadTask: Task<Void, Never>?
    @ObservationIgnored
    private var seekTask: Task<Void, Never>?

    #if os(iOS)
    @ObservationIgnored
    private var automaticPiPObservation: AnyCancellable?
    let pictureInPicture: AetherPictureInPictureCoordinator
    #endif

    init() {
        do {
            self.engine = try AetherEngine()
        } catch {
            fatalError("Unable to initialize AetherEngine: \(error)")
        }

        #if os(iOS)
        pictureInPicture = AetherPictureInPictureCoordinator(engine: engine)
        automaticPiPObservation = observeAutomaticPictureInPicture()
        #endif

        bindEngine()
    }

    isolated deinit {
        stop()
    }

    func load(_ item: MediaPlayerItem) {
        stop()
        loadedItem = item
        item.setTrackIndexes(.init())
        load(item, startSeconds: item.baseItem.isLiveStream ? nil : item.baseItem.startSeconds)
    }

    func play() {
        guard loadedItem != nil else { return }

        engine.play()
        engine.setRate(desiredRate)
    }

    func pause() {
        guard loadedItem != nil else { return }

        engine.pause()
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        seekTask?.cancel()
        seekTask = nil
        loadedItem = nil
        isReady = false
        engine.stop()
        videoState = VideoPlaybackState()
    }

    func setRate(_ rate: Double) {
        desiredRate = Float(rate)

        guard engine.state == .playing else { return }

        engine.setRate(desiredRate)
    }

    func seek(_ request: PlaybackTimeline.Seek) {
        guard let loadedItem, isReady else {
            mediaSession?.playerDidCompleteSeek(request, position: nil, from: self)
            return
        }

        seekTask?.cancel()

        // The engine ignores transport calls once playback ended; reload at the target instead.
        if engine.state == .ended {
            load(loadedItem, startSeconds: request.target, completing: request)
            return
        }

        seekTask = Task { [weak self] in
            guard let self else { return }

            await engine.seek(to: max(0, request.target.seconds))
            guard !Task.isCancelled else { return }

            mediaSession?.playerDidCompleteSeek(request, position: .seconds(engine.currentTime), from: self)
        }
    }

    func cancelSeek() {
        seekTask?.cancel()
        seekTask = nil
    }

    func setStream(_ stream: MediaStream) {
        guard loadedItem != nil else { return }

        switch stream.type {
        case .audio:
            guard let index = stream.index, index >= 0 else { return }

            engine.selectAudioTrack(index: index)

        case .subtitle:
            guard let index = stream.index, index >= 0 else {
                engine.clearSubtitle()
                return
            }

            engine.selectSubtitleTrack(index: index)

        default:
            return
        }
    }

    func videoPlayerBody(layout: VideoPlayer.VideoLayout) -> some View {
        AetherPlayerView(engine: engine, layout: layout)
    }
}

// MARK: - Loading

private extension AetherMediaPlayer {

    func load(_ item: MediaPlayerItem, startSeconds: Duration?, completing seek: PlaybackTimeline.Seek? = nil) {
        loadTask?.cancel()
        isReady = false

        let client = mediaSession?.userSession.client

        let sidecars: [(stream: MediaStream, track: ExternalSubtitleTrack)] = item.subtitleStreams.sidecarSubtitles.compactMap { stream in
            guard let url = client.flatMap({ stream.url(with: $0) }) ?? stream.deliveryURL.flatMap(URL.init(string:)) else { return nil }

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

        loadTask = Task { [weak self, weak item] in
            guard let self, let item else { return }

            do {
                engine.setExternalMetadata(item.baseItem.avMetadata)

                let probe = try await engine.load(
                    url: item.url,
                    startPosition: startSeconds.map { max(0, $0.seconds) },
                    options: options,
                    audioSourceStreamIndex: initialAudioIndex
                )
                try Task.checkCancellation()
                guard loadedItem === item else { return }

                if let probe, probe.videoWidth > 0, probe.videoHeight > 0 {
                    videoState.videoSize = CGSize(width: Int(probe.videoWidth), height: Int(probe.videoHeight))
                }

                item.setTrackIndexes(trackIndexMap(for: item, sidecars: sidecars.map(\.stream)))
                item.applyPlaybackOffsets()

                isReady = true
                publishPlaybackState()

                if mediaSession?.playbackRequestStatus == .playing {
                    play()
                    mediaSession?.playerDidRequestPlayback(.playing, from: self)
                } else {
                    pause()
                    mediaSession?.playerDidRequestPlayback(.paused, from: self)
                }

                if let seek {
                    mediaSession?.playerDidCompleteSeek(seek, position: .seconds(engine.currentTime), from: self)
                }
            } catch is CancellationError {
                // A newer item, seek reload, or an explicit stop superseded this load.
            } catch {
                guard loadedItem === item else { return }

                if let seek {
                    mediaSession?.playerDidCompleteSeek(seek, position: nil, from: self)
                }

                mediaSession?.playerDidFail(ErrorMessage("AetherEngine failed to load media: \(error.localizedDescription)"), from: self)
            }
        }
    }

    /// Maps Jellyfin stream indexes to the track IDs AetherEngine actually probed.
    func trackIndexMap(for item: MediaPlayerItem, sidecars: [MediaStream]) -> MediaTrackIndexMap {
        var map = MediaTrackIndexMap()

        if item.mediaSource.transcodingURL != nil {
            if let selected = item.selectedAudioStreamIndex, let track = engine.audioTracks.first {
                map.setPlayerIndex(track.id, for: selected)
            }
        } else {
            for (stream, track) in zip(item.audioStreams.filter { $0.isExternal != true }, engine.audioTracks) {
                if let index = stream.index { map.setPlayerIndex(track.id, for: index) }
            }
        }

        let embeddedSubtitles = item.subtitleStreams.filter { $0.isExternal != true && $0.deliveryMethod != .encode }
        for (stream, track) in zip(embeddedSubtitles, engine.subtitleTracks.filter { !$0.isExternal }) {
            if let index = stream.index { map.setPlayerIndex(track.id, for: index) }
        }

        for (stream, track) in zip(sidecars, engine.subtitleTracks.filter(\.isExternal)) {
            if let index = stream.index { map.setPlayerIndex(track.id, for: index) }
        }

        return map
    }
}

// MARK: - Engine observation

private extension AetherMediaPlayer {

    func bindEngine() {
        engine.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self, let item = loadedItem else { return }

                switch state {
                case .playing:
                    engine.setRate(desiredRate)

                case .ended:
                    if !item.baseItem.isLiveStream {
                        mediaSession?.ended(from: self)
                    }

                case let .error(message):
                    mediaSession?.playerDidFail(ErrorMessage("AetherEngine playback failed: \(message)"), from: self)

                default:
                    break
                }

                publishPlaybackState()
            }
            .store(in: &engineCancellables)

        engine.$isBuffering
            .removeDuplicates()
            .sink { [weak self] _ in self?.publishPlaybackState() }
            .store(in: &engineCancellables)

        engine.$duration
            .removeDuplicates()
            .sink { [weak self] _ in self?.publishPlaybackState() }
            .store(in: &engineCancellables)

        // Updating the session at Aether's transport-clock cadence can monopolize
        // the main actor and starve the software playback path.
        engine.clock
            .$currentTime
            .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] seconds in
                guard let self, loadedItem != nil, seconds.isFinite else { return }

                mediaSession?.playerDidUpdatePosition(.seconds(seconds), from: self)
            }
            .store(in: &engineCancellables)
    }

    func publishPlaybackState() {
        guard loadedItem != nil else { return }

        let state = engine.state
        let duration = engine.duration

        mediaSession?.playerDidUpdate(
            PlaybackState(
                isReady: isReady,
                isPlaying: state == .playing,
                isSeekable: isReady && (state != .loading),
                isSeeking: state == .seeking,
                duration: duration > 0 && duration.isFinite ? .seconds(duration) : nil,
                isBuffering: engine.isBuffering || state == .loading
            ),
            from: self
        )
    }
}

// MARK: - Video

extension AetherMediaPlayer {

    private struct AetherPlayerView: View {

        let engine: AetherEngine
        let layout: VideoPlayer.VideoLayout

        var body: some View {
            ZStack {
                Color.black

                AetherPlayerSurface(engine: engine)
                    .frame(width: layout.renderSize.width, height: layout.renderSize.height)
                    .scaleEffect(layout.renderScale)
                    .offset(layout.renderOffset)

                AetherSubtitleOverlay(engine: engine, layout: layout)
            }
            .onAppear { engine.videoGravity = .resizeAspect }
        }
    }

    /// Keeps clock-driven subtitle invalidation below the player surface in
    /// the SwiftUI tree. Otherwise every clock tick calls updateUIView on the
    /// render surface while the software decoder is also trying to present.
    private struct AetherSubtitleOverlay: View {

        @ObservedObject
        var engine: AetherEngine

        let layout: VideoPlayer.VideoLayout

        @State
        private var currentTime: Double = 0

        var body: some View {
            let cues = engine.subtitleCues.filter { $0.startTime <= currentTime && currentTime < $0.endTime }

            ZStack {
                // Text cues share the caption styling used by the other players.
                TextSubtitleOverlay(
                    snapshot: TextSubtitleSnapshot(regions: cues.compactMap { cue -> TextSubtitleRegion? in
                        switch cue.body {
                        case let .text(text):
                            return TextSubtitleRegion(text: text)
                        case let .richText(runs):
                            return TextSubtitleRegion(text: runs.map(\.text).joined())
                        case .image:
                            return nil
                        }
                    }),
                    videoLayout: layout
                )

                ForEach(cues) { cue in
                    if case let .image(image) = cue.body {
                        bitmapSubtitle(image.cgImage, position: image.position)
                    }
                }
            }
            .allowsHitTesting(false)
            .onReceive(
                engine.clock
                    .$currentTime
                    .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            ) { seconds in
                guard engine.subtitleCues.isNotEmpty else { return }

                currentTime = seconds
            }
        }

        private func bitmapSubtitle(_ image: CGImage, position: CGRect) -> some View {
            GeometryReader { geometry in
                Image(uiImage: UIImage(cgImage: image))
                    .resizable()
                    .frame(
                        width: max(1, position.width * geometry.size.width),
                        height: max(1, position.height * geometry.size.height)
                    )
                    .position(
                        x: position.midX * geometry.size.width,
                        y: position.midY * geometry.size.height
                    )
            }
        }
    }
}

// MARK: - Picture in Picture

#if os(iOS)

extension AetherMediaPlayer: MediaPlayerPictureInPictureProviding {

    var allowsAutomaticPiP: Bool {
        get { pictureInPicture.allowsAutomaticStart }
        set { pictureInPicture.allowsAutomaticStart = newValue }
    }

    var isPiPActive: Bool {
        pictureInPicture.isActive
    }

    var isPiPAvailable: Bool {
        pictureInPicture.isAvailable
    }

    var isPiPTransitioning: Bool {
        pictureInPicture.isTransitioning
    }

    func startPiP() {
        pictureInPicture.start()
    }

    func stopPiP() {
        pictureInPicture.stop()
    }
}

@MainActor
@Observable
final class AetherPictureInPictureCoordinator: NSObject,
    AVPictureInPictureControllerDelegate,
    AVPictureInPictureSampleBufferPlaybackDelegate
{

    private(set) var isActive = false
    private(set) var isAvailable = false
    private(set) var isTransitioning = false

    var allowsAutomaticStart = false {
        didSet {
            controller?.canStartPictureInPictureAutomaticallyFromInline = allowsAutomaticStart
        }
    }

    @ObservationIgnored
    private weak var engine: AetherEngine?
    @ObservationIgnored
    private var availabilityObservation: NSKeyValueObservation?
    @ObservationIgnored
    private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored
    private var controller: AVPictureInPictureController?
    @ObservationIgnored
    private var softwareSource: SoftwarePiPSource?
    @ObservationIgnored
    private var sourceIdentity: ObjectIdentifier?

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

    func start() {
        isTransitioning = true
        controller?.startPictureInPicture()
    }

    func stop() {
        isTransitioning = true
        controller?.stopPictureInPicture()
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
                isAvailable = false
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
            controller.canStartPictureInPictureAutomaticallyFromInline = allowsAutomaticStart
            self.controller = controller
            availabilityObservation = controller.observe(\.isPictureInPicturePossible, options: [
                .initial,
                .new,
            ]) { [weak self] controller, _ in
                Task { @MainActor in self?.isAvailable = controller.isPictureInPicturePossible }
            }
        }
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        engine?.pictureInPictureActive = true
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isTransitioning = false
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
        isTransitioning = false
        engine?.pictureInPictureActive = false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        isActive = false
        isTransitioning = false
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
