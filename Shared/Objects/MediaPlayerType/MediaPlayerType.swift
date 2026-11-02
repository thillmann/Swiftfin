//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI

enum MediaPlayerType: String, CaseIterable, Displayable, Storable {

    case avPlayer
    case mpv
    case aether

    // Raw values are persisted in Defaults and offline metadata.
    // VLC has been removed; its stored values fall back to MPV.
    init?(rawValue: String) {
        switch rawValue {
        case "native", "avPlayer": self = .avPlayer
        case "swiftfin", "vlc", "mpv": self = .mpv
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
        case .mpv:
            Self._mpvDirectPlayProfiles
        }
    }

    var transcodingProfiles: [TranscodingProfile] {
        switch self {
        case .aether:
            Self._aetherTranscodingProfiles
        case .avPlayer:
            Self._avPlayerTranscodingProfiles
        case .mpv:
            Self._mpvTranscodingProfiles
        }
    }

    var subtitleProfiles: [SubtitleProfile] {
        switch self {
        case .aether:
            Self._aetherSubtitleProfiles
        case .avPlayer:
            Self._avPlayerSubtitleProfiles
        case .mpv:
            Self._mpvSubtitleProfiles
        }
    }

    @MainActor
    func makePlayer() -> any MediaPlayer {
        switch self {
        case .aether:
            AetherMediaPlayer()
        case .avPlayer:
            AVMediaPlayer()
        case .mpv:
            MPVMediaPlayer()
        }
    }
}
