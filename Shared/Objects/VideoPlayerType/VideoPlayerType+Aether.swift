//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

extension VideoPlayerType {

    // Keep this experimental profile deliberately narrower than VLCKit.
    // It advertises only formats covered by AetherEngine's native or
    // software pipelines and lets Jellyfin transcode everything else.

    // MARK: - Direct Play

    @ArrayBuilder<DirectPlayProfile>
    static var _aetherDirectPlayProfiles: [DirectPlayProfile] {
        DirectPlayProfile(type: .video) {
            AudioCodec.aac
            AudioCodec.ac3
            AudioCodec.alac
            AudioCodec.dts
            AudioCodec.eac3
            AudioCodec.flac
            AudioCodec.mp2
            AudioCodec.mp3
            AudioCodec.opus
            AudioCodec.pcm_s16be
            AudioCodec.pcm_s16le
            AudioCodec.pcm_s24be
            AudioCodec.pcm_s24le
            AudioCodec.vorbis
        } videoCodecs: {
            VideoCodec.av1
            VideoCodec.h264
            VideoCodec.hevc
            VideoCodec.mjpeg
            VideoCodec.mpeg1video
            VideoCodec.mpeg2video
            VideoCodec.mpeg4
            VideoCodec.vc1
            VideoCodec.vp8
            VideoCodec.vp9
        } containers: {
            MediaContainer.avi
            MediaContainer.flv
            MediaContainer.m4v
            MediaContainer.mkv
            MediaContainer.mov
            MediaContainer.mp4
            MediaContainer.mpegts
            MediaContainer.ts
            MediaContainer.webm
        }
    }

    // MARK: - Transcoding

    static var _aetherTranscodingProfiles: [TranscodingProfile] {
        _vlcTranscodingProfiles
    }

    // MARK: - Subtitles

    @ArrayBuilder<SubtitleProfile>
    static var _aetherSubtitleProfiles: [SubtitleProfile] {
        SubtitleProfile.build(method: .embed) {
            SubtitleFormat.ass
            SubtitleFormat.cc_dec
            SubtitleFormat.dvbsub
            SubtitleFormat.dvdsub
            SubtitleFormat.libzvbi_teletextdec
            SubtitleFormat.mov_text
            SubtitleFormat.pgssub
            SubtitleFormat.ssa
            SubtitleFormat.subrip
            SubtitleFormat.text
            SubtitleFormat.vtt
            SubtitleFormat.xsub
        }

        SubtitleProfile.build(method: .external) {
            SubtitleFormat.ass
            SubtitleFormat.ssa
            SubtitleFormat.subrip
            SubtitleFormat.text
            SubtitleFormat.vtt
        }

        // Image-based external tracks still need server-side rendering.
        SubtitleProfile.build(method: .encode) {
            SubtitleFormat.dvbsub
            SubtitleFormat.dvdsub
            SubtitleFormat.pgssub
            SubtitleFormat.xsub
        }
    }

    // MARK: - Codec Profiles

    static var _aetherCodecProfiles: [CodecProfile] {
        _vlcCodecProfiles
    }
}
