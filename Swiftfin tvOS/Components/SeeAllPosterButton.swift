//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct SeeAllPosterButton: View {

    let type: PosterDisplayType
    let title: String
    let action: () -> Void

    init(
        type: PosterDisplayType,
        title: String = L10n.seeAll,
        action: @escaping () -> Void
    ) {
        self.type = type
        self.title = title
        self.action = action
    }

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Color(UIColor.darkGray)
                    .opacity(0.46)

                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                VStack {
                    Spacer()

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .posterStyle(type)
        }
        .buttonStyle(.card)
        .accessibilityLabel(title)
    }
}
