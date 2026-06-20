//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

enum HeroScrollPresentation: Hashable {
    case hero
    case belowHero
}

struct HeroScrollView<Content: View>: View {

    @Binding
    private var presentation: HeroScrollPresentation

    private let heroAnchor: UnitPoint
    private let belowHeroAnchor: UnitPoint
    private let content: Content

    init(
        presentation: Binding<HeroScrollPresentation>,
        heroAnchor: UnitPoint = .top,
        belowHeroAnchor: UnitPoint = .top,
        @ViewBuilder content: () -> Content
    ) {
        _presentation = presentation
        self.heroAnchor = heroAnchor
        self.belowHeroAnchor = belowHeroAnchor
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                content
            }
            .onChange(of: presentation) { _, newValue in
                withAnimation(.easeOut(duration: 0.6)) {
                    proxy.scrollTo(newValue, anchor: anchor(for: newValue))
                }
            }
        }
    }

    private func anchor(for presentation: HeroScrollPresentation) -> UnitPoint {
        switch presentation {
        case .hero:
            heroAnchor
        case .belowHero:
            belowHeroAnchor
        }
    }
}
