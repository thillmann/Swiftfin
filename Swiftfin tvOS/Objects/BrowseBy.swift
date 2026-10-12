//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftUI

struct BrowseByOption: Hashable, Identifiable {

    enum Kind: String, Hashable {
        case movieStudio
        case tvNetwork

        var mediaType: SeerrClient.MediaResult.MediaType {
            switch self {
            case .movieStudio:
                .movie
            case .tvNetwork:
                .tv
            }
        }

        var routePrefix: String {
            switch self {
            case .movieStudio:
                "studio"
            case .tvNetwork:
                "network"
            }
        }

        func discover(
            optionID: Int,
            page: Int,
            language: String?
        ) async -> Result<SeerrClient.Page<SeerrClient.MediaResult>, SeerrClient.ProbeError> {
            switch self {
            case .movieStudio:
                await SeerrClient.discoverStudioMovies(studioID: optionID, page: page, language: language)
            case .tvNetwork:
                await SeerrClient.discoverNetworkTV(networkID: optionID, page: page, language: language)
            }
        }
    }

    enum LogoRenderingMode: Hashable {
        case template
        case original

        var imageRenderingMode: Image.TemplateRenderingMode {
            switch self {
            case .template:
                .template
            case .original:
                .original
            }
        }
    }

    struct Logo: Hashable {
        let assetName: String
        let frameSize: CGSize
        let renderingMode: LogoRenderingMode
        let offset: CGSize

        init(
            assetName: String,
            frameSize: CGSize,
            renderingMode: LogoRenderingMode = .template,
            offset: CGSize = .zero
        ) {
            self.assetName = assetName
            self.frameSize = frameSize
            self.renderingMode = renderingMode
            self.offset = offset
        }
    }

    struct Theme: Hashable {
        let background: UInt32
        let secondary: UInt32
        let glow: UInt32

        var backgroundColor: Color {
            Color(hex: background)
        }

        var secondaryColor: Color {
            Color(hex: secondary)
        }

        var glowColor: Color {
            Color(hex: glow)
        }
    }

    let kind: Kind
    let seerrID: Int
    let name: String
    let railLogo: Logo
    let heroLogo: Logo
    let displayLogo: Logo
    let tagline: String
    let theme: Theme

    var id: String {
        "\(kind.rawValue)-\(seerrID)"
    }
}

struct BrowseByGroup: Hashable, Identifiable {

    enum ID: Hashable {
        case studios
        case networks
    }

    let id: ID
    let title: String
    let options: [BrowseByOption]

    var initialOption: BrowseByOption {
        options[0]
    }

    init(
        id: ID,
        title: String,
        options: [BrowseByOption]
    ) {
        precondition(!options.isEmpty, "Browse by groups must include at least one option.")

        self.id = id
        self.title = title
        self.options = options
    }
}

private extension Color {

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
