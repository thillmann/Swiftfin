//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension BrowseByGroup {

    static let studios = BrowseByGroup(
        id: .studios,
        title: L10n.browseMoviesByStudio,
        options: [
            .init(
                kind: .movieStudio,
                seerrID: 2,
                name: "Walt Disney Pictures",
                railLogo: .init(
                    assetName: "studio-disney-rail",
                    frameSize: CGSize(width: 102, height: 34),
                    offset: CGSize(width: 0, height: 2)
                ),
                heroLogo: .init(assetName: "studio-disney-rail", frameSize: CGSize(width: 280, height: 118)),
                displayLogo: .init(assetName: "studio-disney-rail", frameSize: CGSize(width: 360, height: 124)),
                tagline: L10n.studioDisneyTagline,
                theme: .init(background: 0x123C69, secondary: 0x0B1026, glow: 0xBDEBFF)
            ),
            .init(
                kind: .movieStudio,
                seerrID: 3,
                name: "Pixar",
                railLogo: .init(assetName: "studio-pixar-rail", frameSize: CGSize(width: 108, height: 36)),
                heroLogo: .init(assetName: "studio-pixar-rail", frameSize: CGSize(width: 300, height: 90)),
                displayLogo: .init(assetName: "studio-pixar-rail", frameSize: CGSize(width: 360, height: 124)),
                tagline: L10n.studioPixarTagline,
                theme: .init(background: 0x1F78B4, secondary: 0x071D33, glow: 0xA7E4FF)
            ),
            .init(
                kind: .movieStudio,
                seerrID: 420,
                name: "Marvel Studios",
                railLogo: .init(assetName: "studio-marvel-rail", frameSize: CGSize(width: 108, height: 36)),
                heroLogo: .init(
                    assetName: "studio-marvel-display",
                    frameSize: CGSize(width: 335, height: 84),
                    renderingMode: .original
                ),
                displayLogo: .init(
                    assetName: "studio-marvel-display",
                    frameSize: CGSize(width: 360, height: 124),
                    renderingMode: .original
                ),
                tagline: L10n.studioMarvelTagline,
                theme: .init(background: 0x8A0D13, secondary: 0x1A0508, glow: 0xFF9D9D)
            ),
            .init(
                kind: .movieStudio,
                seerrID: 174,
                name: "Warner Bros. Pictures",
                railLogo: .init(assetName: "studio-warner-bros-rail", frameSize: CGSize(width: 74, height: 42)),
                heroLogo: .init(
                    assetName: "studio-warner-bros-display",
                    frameSize: CGSize(width: 132, height: 128),
                    renderingMode: .original
                ),
                displayLogo: .init(
                    assetName: "studio-warner-bros-display",
                    frameSize: CGSize(width: 360, height: 124),
                    renderingMode: .original
                ),
                tagline: L10n.studioWarnerBrosTagline,
                theme: .init(background: 0x0D3B66, secondary: 0x081729, glow: 0x8FD3FF)
            ),
            .init(
                kind: .movieStudio,
                seerrID: 33,
                name: "Universal Pictures",
                railLogo: .init(assetName: "studio-universal-rail", frameSize: CGSize(width: 108, height: 36)),
                heroLogo: .init(assetName: "studio-universal-rail", frameSize: CGSize(width: 225, height: 120)),
                displayLogo: .init(assetName: "studio-universal-rail", frameSize: CGSize(width: 360, height: 124)),
                tagline: L10n.studioUniversalTagline,
                theme: .init(background: 0x162B6F, secondary: 0x050816, glow: 0xF0C15A)
            ),
            .init(
                kind: .movieStudio,
                seerrID: 4,
                name: "Paramount Pictures",
                railLogo: .init(assetName: "studio-paramount-rail", frameSize: CGSize(width: 108, height: 36)),
                heroLogo: .init(assetName: "studio-paramount-rail", frameSize: CGSize(width: 190, height: 132)),
                displayLogo: .init(assetName: "studio-paramount-rail", frameSize: CGSize(width: 360, height: 124)),
                tagline: L10n.studioParamountTagline,
                theme: .init(background: 0x153A7A, secondary: 0x061225, glow: 0xFFFFFF)
            ),
            .init(
                kind: .movieStudio,
                seerrID: 34,
                name: "Sony Pictures",
                railLogo: .init(assetName: "studio-sony-rail", frameSize: CGSize(width: 108, height: 36)),
                heroLogo: .init(assetName: "studio-sony-rail", frameSize: CGSize(width: 96, height: 132)),
                displayLogo: .init(assetName: "studio-sony-rail", frameSize: CGSize(width: 360, height: 124)),
                tagline: L10n.studioSonyTagline,
                theme: .init(background: 0x271D54, secondary: 0x080817, glow: 0x6BE7FF)
            ),
            .init(
                kind: .movieStudio,
                seerrID: 127_928,
                name: "20th Century Studios",
                railLogo: .init(assetName: "studio-20th-century-rail", frameSize: CGSize(width: 108, height: 36)),
                heroLogo: .init(assetName: "studio-20th-century-rail", frameSize: CGSize(width: 160, height: 132)),
                displayLogo: .init(assetName: "studio-20th-century-rail", frameSize: CGSize(width: 260, height: 172)),
                tagline: L10n.studioTwentiethCenturyTagline,
                theme: .init(background: 0x5F3B12, secondary: 0x100904, glow: 0xFFD98A)
            ),
            .init(
                kind: .movieStudio,
                seerrID: 521,
                name: "DreamWorks Animation",
                railLogo: .init(assetName: "studio-dreamworks-rail", frameSize: CGSize(width: 108, height: 36)),
                heroLogo: .init(assetName: "studio-dreamworks-display", frameSize: CGSize(width: 300, height: 92)),
                displayLogo: .init(assetName: "studio-dreamworks-display", frameSize: CGSize(width: 360, height: 124)),
                tagline: L10n.studioDreamWorksTagline,
                theme: .init(background: 0x3B1D6A, secondary: 0x080414, glow: 0x7CE3FF)
            ),
            .init(
                kind: .movieStudio,
                seerrID: 9993,
                name: "DC",
                railLogo: .init(assetName: "studio-dc-rail", frameSize: CGSize(width: 108, height: 36)),
                heroLogo: .init(
                    assetName: "studio-dc-display",
                    frameSize: CGSize(width: 126, height: 126),
                    renderingMode: .original
                ),
                displayLogo: .init(
                    assetName: "studio-dc-display",
                    frameSize: CGSize(width: 360, height: 124),
                    renderingMode: .original
                ),
                tagline: L10n.studioDcTagline,
                theme: .init(background: 0x0B3D91, secondary: 0x020916, glow: 0x8FD3FF)
            ),
            .init(
                kind: .movieStudio,
                seerrID: 41077,
                name: "A24",
                railLogo: .init(assetName: "studio-a24-rail", frameSize: CGSize(width: 108, height: 36)),
                heroLogo: .init(assetName: "studio-a24-rail", frameSize: CGSize(width: 220, height: 90)),
                displayLogo: .init(assetName: "studio-a24-rail", frameSize: CGSize(width: 360, height: 124)),
                tagline: L10n.studioA24Tagline,
                theme: .init(background: 0x222222, secondary: 0x050505, glow: 0xFFFFFF)
            ),
        ]
    )
}
