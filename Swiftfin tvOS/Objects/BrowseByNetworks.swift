//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension BrowseByGroup {

    static let networks = BrowseByGroup(
        id: .networks,
        title: L10n.browseTVShowsByNetwork,
        options: [
            BrowseByOption.network(
                id: 213,
                name: "Netflix",
                logoAssetName: "network-netflix",
                heroLogoAssetName: "network-netflix-wordmark",
                railLogoSize: CGSize(width: 72, height: 42),
                heroLogoSize: CGSize(width: 300, height: 88),
                tagline: L10n.networkNetflixTagline,
                theme: .init(background: 0x8A0710, secondary: 0x150205, glow: 0xFF6A6A)
            ),
            BrowseByOption.network(
                id: 49,
                name: "HBO",
                logoAssetName: "network-hbo",
                railLogoSize: CGSize(width: 96, height: 40),
                railLogoOffset: CGSize(width: 6, height: 0),
                heroLogoSize: CGSize(width: 266, height: 104),
                tagline: L10n.networkHboTagline,
                theme: .init(background: 0x202A44, secondary: 0x05070E, glow: 0xB8C7FF)
            ),
            BrowseByOption.network(
                id: 453,
                name: "Hulu",
                logoAssetName: "network-hulu",
                railLogoSize: CGSize(width: 88, height: 28),
                heroLogoSize: CGSize(width: 268, height: 86),
                tagline: L10n.networkHuluTagline,
                theme: .init(background: 0x0B5F3A, secondary: 0x02130B, glow: 0xA3FFCB)
            ),
            BrowseByOption.network(
                id: 2552,
                name: "Apple TV+",
                logoAssetName: "network-apple-tv",
                railLogoSize: CGSize(width: 98, height: 40),
                heroLogoSize: CGSize(width: 272, height: 106),
                tagline: L10n.networkAppleTVTagline,
                theme: .init(background: 0x2A2A2D, secondary: 0x050506, glow: 0xF5F5F7)
            ),
            BrowseByOption.network(
                id: 1024,
                name: "Prime Video",
                logoAssetName: "network-prime-video",
                railLogoSize: CGSize(width: 112, height: 40),
                heroLogoSize: CGSize(width: 300, height: 104),
                tagline: L10n.networkPrimeVideoTagline,
                theme: .init(background: 0x123A6B, secondary: 0x04101F, glow: 0x7DCEFF)
            ),
            BrowseByOption.network(
                id: 2739,
                name: "Disney+",
                logoAssetName: "network-disney-plus",
                railLogoSize: CGSize(width: 126, height: 44),
                heroLogoSize: CGSize(width: 330, height: 122),
                tagline: L10n.networkDisneyPlusTagline,
                theme: .init(background: 0x113C7A, secondary: 0x061226, glow: 0x9EDBFF)
            ),
            BrowseByOption.network(
                id: 174,
                name: "AMC",
                logoAssetName: "network-amc",
                railLogoSize: CGSize(width: 98, height: 40),
                heroLogoSize: CGSize(width: 250, height: 104),
                tagline: L10n.networkAMCTagline,
                theme: .init(background: 0x2E2718, secondary: 0x080704, glow: 0xE5C16C)
            ),
            BrowseByOption.network(
                id: 88,
                name: "FX",
                logoAssetName: "network-fx",
                railLogoSize: CGSize(width: 76, height: 38),
                heroLogoSize: CGSize(width: 190, height: 96),
                tagline: L10n.networkFXTagline,
                theme: .init(background: 0x1D2430, secondary: 0x05070A, glow: 0xC6D2E8)
            ),
        ]
    )
}

private extension BrowseByOption {

    static func network(
        id: Int,
        name: String,
        logoAssetName: String,
        heroLogoAssetName: String? = nil,
        railLogoSize: CGSize,
        railLogoOffset: CGSize = .zero,
        heroLogoSize: CGSize,
        tagline: String,
        theme: BrowseByOption.Theme,
        displayLogoSize: CGSize = CGSize(width: 360, height: 124)
    ) -> BrowseByOption {
        .init(
            kind: .tvNetwork,
            seerrID: id,
            name: name,
            railLogo: .init(assetName: logoAssetName, frameSize: railLogoSize, offset: railLogoOffset),
            heroLogo: .init(assetName: heroLogoAssetName ?? logoAssetName, frameSize: heroLogoSize),
            displayLogo: .init(assetName: heroLogoAssetName ?? logoAssetName, frameSize: displayLogoSize),
            tagline: tagline,
            theme: theme
        )
    }
}
