//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct UnifiedMediaResultPosterOverlay: View {

    @Environment(\.isPosterFocused)
    private var isPosterFocused

    let item: UnifiedMediaResult

    private var overlayOpacity: Double {
        isPosterFocused ? 1 : 0.55
    }

    var body: some View {
        if case .seerr = item {
            ZStack(alignment: .topTrailing) {
                Color.clear

                HStack(spacing: 6) {
                    Spacer()

                    if let seerrStatusPillText = item.seerrStatusPillText {
                        Text(seerrStatusPillText)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                    }

                    Image("seerr.monochrome")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .padding(7)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .padding(.top, 12)
                .padding(.trailing, 12)
                .opacity(overlayOpacity)
                .animation(.easeInOut(duration: 0.15), value: isPosterFocused)
            }
            .allowsHitTesting(false)
        }
    }
}
