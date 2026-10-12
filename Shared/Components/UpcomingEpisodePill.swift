//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct UpcomingEpisodePillLoader: View {

    let item: BaseItemDto
    let userSession: UserSession?

    @State
    private var label: String?

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            if let label {
                UpcomingEpisodePill(label: label)
            }
        }
        .task(id: item.id) {
            label = nil

            guard let userSession else { return }

            let newLabel = await UpcomingEpisodeProvider.pillLabel(
                for: item,
                userSession: userSession
            )

            guard !Task.isCancelled else { return }

            label = newLabel
        }
    }
}

struct UpcomingEpisodePill: View {

    let label: String

    var body: some View {
        Text(label)
            .font(font)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background {
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.38))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    private var font: Font {
        #if os(tvOS)
        .caption2.weight(.semibold)
        #else
        .caption.weight(.semibold)
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        24
        #else
        14
        #endif
    }

    private var height: CGFloat {
        #if os(tvOS)
        52
        #else
        32
        #endif
    }
}
