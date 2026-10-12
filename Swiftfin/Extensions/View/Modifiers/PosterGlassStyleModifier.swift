//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

private struct PosterGlassStyleModifier: ViewModifier {

    let type: PosterDisplayType

    private var shape: RoundedRectangle {
        let cornerRadius: CGFloat = type == .landscape ? 16 : 14
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let shapedContent = content.containerShape(shape)

        if #available(iOS 26.0, *) {
            if type == .portrait {
                shapedContent
                    .glassEffect(.clear, in: shape)
                    .clipShape(shape)
            } else {
                shapedContent
                    .glassEffect(.clear, in: shape)
                    .compositingGroup()
                    .clipShape(shape)
            }
        } else if type == .portrait {
            shapedContent
                .clipShape(shape)
                .overlay {
                    shape
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
        } else {
            shapedContent
                .compositingGroup()
                .clipShape(shape)
                .overlay {
                    shape
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
        }
    }
}

extension View {

    func posterGlassStyle(_ type: PosterDisplayType) -> some View {
        modifier(PosterGlassStyleModifier(type: type))
    }
}
