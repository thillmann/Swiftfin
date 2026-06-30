//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftUI

@MainActor
protocol SeerrRequestStateUpdating: AnyObject {
    func markRequested(_ requestedItem: SeerrClient.MediaResult)
}

enum UnifiedMediaResult: Identifiable {
    case jellyfin(BaseItemDto)
    case seerr(SeerrClient.MediaResult)

    var id: String {
        switch self {
        case let .jellyfin(item):
            "jellyfin-\(item.id ?? item.displayTitle)"
        case let .seerr(item):
            "seerr-\(item.mediaType?.rawValue ?? "unknown")-\(item.id)"
        }
    }

    var kind: BaseItemKind? {
        switch self {
        case let .jellyfin(item):
            item.type
        case let .seerr(item):
            switch item.mediaType {
            case .movie:
                .movie
            case .tv:
                .series
            case .person:
                .person
            case nil:
                nil
            }
        }
    }

    var title: String {
        switch self {
        case let .jellyfin(item):
            item.displayTitle
        case let .seerr(item):
            item.title ?? item.name ?? L10n.unknown
        }
    }

    var imageSources: [ImageSource] {
        switch self {
        case let .jellyfin(item):
            item.thumbImageSources()
        case let .seerr(item):
            [item.posterImageSource]
        }
    }
}

extension UnifiedMediaResult: Hashable {
    static func == (lhs: UnifiedMediaResult, rhs: UnifiedMediaResult) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension UnifiedMediaResult: Displayable {
    var displayTitle: String {
        title
    }
}

extension UnifiedMediaResult: LibraryIdentifiable {
    var unwrappedIDHashOrZero: Int {
        id.hashValue
    }
}

extension UnifiedMediaResult: SystemImageable {
    var systemImage: String {
        switch self {
        case let .jellyfin(item):
            item.systemImage
        case let .seerr(item):
            switch item.mediaType {
            case .movie:
                "film"
            case .tv:
                "tv"
            case .person:
                "person"
            case nil:
                "questionmark"
            }
        }
    }
}

extension UnifiedMediaResult: Poster {
    typealias ImageBody = Image

    var preferredPosterDisplayType: PosterDisplayType {
        switch kind {
        case .person:
            .portrait
        case .movie, .series:
            .portrait
        default:
            .portrait
        }
    }

    func portraitImageSources(maxWidth _: CGFloat?, quality _: Int?) -> [ImageSource] {
        imageSources
    }

    func landscapeImageSources(maxWidth _: CGFloat?, quality _: Int?) -> [ImageSource] {
        imageSources
    }

    func cinematicImageSources(maxWidth _: CGFloat?, quality _: Int?) -> [ImageSource] {
        imageSources
    }

    func squareImageSources(maxWidth _: CGFloat?, quality _: Int?) -> [ImageSource] {
        imageSources
    }

    var subtitle: String? {
        nil
    }

    var seerrStatusPillText: String? {
        guard case let .seerr(item) = self else { return nil }
        guard let status = item.mediaInfo?.mediaStatus else { return nil }
        guard status != .unknown else { return nil }

        return switch status {
        case .pending:
            L10n.seerrStatusRequested
        case .processing:
            L10n.seerrStatusProcessing
        case .partiallyAvailable:
            L10n.seerrStatusPartial
        case .available:
            L10n.seerrStatusAvailable
        case .unknown:
            nil
        }
    }
}
