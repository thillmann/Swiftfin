//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI

enum VideoPlayerType: String, CaseIterable, Displayable, SupportedCaseIterable, Storable {

    case avPlayer = "native"
    case vlc
    case mpv
    case aether

    // Raw values are persisted in Defaults and offline metadata.
    init?(rawValue: String) {
        switch rawValue {
        case "native", "avPlayer": self = .avPlayer
        case "swiftfin", "vlc": self = .vlc
        case "mpv": self = .mpv
        case "aether": self = .aether
        default: return nil
        }
    }

    var displayTitle: String {
        switch self {
        case .aether:
            L10n.aether
        case .avPlayer:
            L10n.avPlayer
        case .vlc:
            L10n.vlc
        case .mpv:
            L10n.mpv
        }
    }

    var directPlayProfiles: [DirectPlayProfile] {
        switch self {
        case .aether:
            Self._aetherDirectPlayProfiles
        case .avPlayer:
            Self._avPlayerDirectPlayProfiles
        case .vlc, .mpv:
            Self._vlcDirectPlayProfiles
        }
    }

    var transcodingProfiles: [TranscodingProfile] {
        switch self {
        case .aether:
            Self._aetherTranscodingProfiles
        case .avPlayer:
            Self._avPlayerTranscodingProfiles
        case .vlc, .mpv:
            Self._vlcTranscodingProfiles
        }
    }

    var subtitleProfiles: [SubtitleProfile] {
        switch self {
        case .aether:
            Self._aetherSubtitleProfiles
        case .avPlayer:
            Self._avPlayerSubtitleProfiles
        case .vlc, .mpv:
            Self._vlcSubtitleProfiles
        }
    }

    @ArrayBuilder<VideoPlayerType>
    static var supportedCases: [VideoPlayerType] {
        VideoPlayerType.avPlayer
        VideoPlayerType.vlc
        VideoPlayerType.aether

        if Defaults[.Experimental.mpvPlayer] {
            VideoPlayerType.mpv
        }
    }
}
