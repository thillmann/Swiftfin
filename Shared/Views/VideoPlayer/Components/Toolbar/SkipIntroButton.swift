//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension VideoPlayer.PlaybackControls {

    struct SkipIntroButton: View {

        @EnvironmentObject
        private var manager: MediaPlayerManager

        var body: some View {
            Button {
                manager.skipCurrentIntro()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 18, weight: .semibold))

                    Text(L10n.skipIntro)
                }
            }
            .buttonStyle(SkipIntroButtonStyle())
            .videoPlayerActionButtonTransition()
        }
    }
}

private struct SkipIntroButtonStyle: ButtonStyle {

    @Environment(\.isFocused)
    private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.black.opacity(0.9))
            .padding(.horizontal, 26)
            .frame(height: 52)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(isFocused ? 0.96 : 0.88))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        Color.white.opacity(isFocused ? 0.32 : 0.18),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(isFocused ? 0.28 : 0.18), radius: isFocused ? 12 : 8, y: 5)
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
