//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Renders the shared backdrop treatment for cinematic and compact-logo
/// detail headers.
struct CinematicBackdropView: View {

    let source: ImageSource
    let bottomColor: Color
    let size: CGSize
    let targetAspectRatio: CGFloat
    let alignment: Alignment

    init(
        source: ImageSource,
        bottomColor: Color,
        size: CGSize,
        targetAspectRatio: CGFloat? = nil,
        alignment: Alignment = .center
    ) {
        self.source = source
        self.bottomColor = bottomColor
        self.size = size
        self.targetAspectRatio = targetAspectRatio ?? size.width / size.height
        self.alignment = alignment
    }

    var body: some View {
        SmartCropImageView(
            source,
            targetAspectRatio: targetAspectRatio
        )
        .frame(width: size.width, height: size.height, alignment: alignment)
        .clipped()
        .bottomEdgeGradient(bottomColor: bottomColor)
    }
}
