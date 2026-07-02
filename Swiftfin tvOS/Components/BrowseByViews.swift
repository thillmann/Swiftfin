//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct BrowseByLogoView: View {

    enum Variant: Equatable {
        case rail
        case hero
        case display
    }

    let option: BrowseByOption
    let variant: Variant
    let alignment: Alignment
    let foregroundColor: Color
    let accessibilityLabel: String?

    init(
        option: BrowseByOption,
        variant: Variant = .display,
        alignment: Alignment = .center,
        foregroundColor: Color = .white,
        accessibilityLabel: String? = nil
    ) {
        self.option = option
        self.variant = variant
        self.alignment = alignment
        self.foregroundColor = foregroundColor
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        if let accessibilityLabel {
            logoContent
                .accessibilityLabel(Text(accessibilityLabel))
        } else {
            logoContent
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var logoContent: some View {
        logo
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .clipped()
    }

    @ViewBuilder
    private var logo: some View {
        Image(configuration.assetName)
            .resizable()
            .renderingMode(configuration.renderingMode.imageRenderingMode)
            .scaledToFit()
            .foregroundStyle(foregroundColor)
    }

    private var configuration: BrowseByOption.Logo {
        switch variant {
        case .rail:
            option.railLogo
        case .hero:
            option.heroLogo
        case .display:
            option.displayLogo
        }
    }
}

struct BrowseByThemeBackground: View {

    let option: BrowseByOption

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    option.theme.backgroundColor,
                    option.theme.secondaryColor,
                    .black,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    option.theme.glowColor.opacity(0.55),
                    option.theme.backgroundColor.opacity(0.18),
                    .clear,
                ],
                center: .trailing,
                startRadius: 20,
                endRadius: 620
            )
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    .black.opacity(0.12),
                    .clear,
                    .black.opacity(0.38),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
