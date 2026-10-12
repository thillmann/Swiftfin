//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// The shared blur treatment behind cinematic hero details.
struct CinematicHeroBlurOverlay: View {

    var body: some View {
        BlurView(style: .systemThinMaterialDark)
            .maskLinearGradient {
                (location: 0, opacity: 0)
                (location: 0.15, opacity: 0.02)
                (location: 0.3, opacity: 0.1)
                (location: 0.45, opacity: 0.28)
                (location: 0.58, opacity: 0.52)
                (location: 0.7, opacity: 0.8)
                (location: 0.78, opacity: 1)
                (location: 1, opacity: 1)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
