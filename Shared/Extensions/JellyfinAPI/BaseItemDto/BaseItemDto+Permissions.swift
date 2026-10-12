//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftUI

extension BaseItemDto {

    /// Preserve the platform item's advanced menu visibility using current permissions.
    var showEditorMenu: Bool {
        canEditMetadata || canEditSubtitles
    }

    /// Indicates whether the item can be downloaded by the current user
    var canBeDownloaded: Bool {
        canBeDownloaded(mediaSource: mediaSources?.first)
    }

    /// Indicates whether an exact selected media source can be downloaded.
    /// Jellyfin's item `canDownload` only covers file-backed item paths; finite
    /// HTTP media sources are delivered through the static video proxy.
    func canBeDownloaded(mediaSource: MediaSourceInfo?) -> Bool {
        guard let userPolicy = Container.shared.currentUserSession()?.user.data.policy else { return false }
        guard userPolicy.enableContentDownloading == true,
              [.movie, .episode].contains(type),
              let mediaSource
        else { return false }

        switch DownloadSourceClassifier.kind(itemIsLive: isLiveStream, source: mediaSource) {
        case .file:
            return canDownload == true
        case .finiteHTTP:
            return true
        case .disc, .hls, .live, .unsupported:
            return false
        }
    }

    /// Indicates whether the item's metadata can be edited by the current user
    var canEditMetadata: Bool {
        guard let userPolicy = Container.shared.currentUserSession()?.user.data.policy else { return false }

        switch type {
        case .playlist:
            return canDelete == true
        case .boxSet:
            return userPolicy.enableCollectionManagement == true || userPolicy.isAdministrator == true
        default:
            return userPolicy.isAdministrator == true
        }
    }

    /// Indicates whether the item's lyrics can be edited by the current user
    var canEditLyrics: Bool {
        guard let userPolicy = Container.shared.currentUserSession()?.user.data.policy else { return false }

        switch type {
        case .audio:
            return userPolicy.enableLyricManagement == true || userPolicy.isAdministrator == true
        default:
            return false
        }
    }

    /// Indicates whether the item's subtitles can be edited by the current user
    var canEditSubtitles: Bool {
        guard let userPolicy = Container.shared.currentUserSession()?.user.data.policy else { return false }

        switch type {
        case .episode, .movie, .musicVideo, .trailer, .video:
            return userPolicy.enableSubtitleManagement == true || userPolicy.isAdministrator == true
        default:
            return false
        }
    }
}
