//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ItemView.AboutView {

    struct Card: View {

        @FocusState
        private var isFocused: Bool

        private let content: () -> any View
        private let action: () -> Void
        private let title: String
        private let subtitle: String?

        var body: some View {
            Button {
                action()
            } label: {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let subtitle {
                            Text(subtitle)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }

                    content()
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.92))
                        .eraseToAnyView()
                }
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 34)
                .frame(width: 700, height: 405, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.white.opacity(isFocused ? 0.22 : 0.12))
                }
                .glassLift(
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                    isFocused: isFocused,
                    scale: 1.04,
                    shadowOpacity: 0.18,
                    shadowRadius: 14,
                    shadowY: 8
                )
            }
            .buttonStyle(.focusNeutral)
            .focusEffectDisabled()
            .focused($isFocused)
        }

        init(
            title: String,
            subtitle: String? = nil,
            @ViewBuilder content: @escaping () -> any View
        ) {
            self.init(
                title: title,
                subtitle: subtitle,
                action: {},
                content: content
            )
        }

        init(
            title: String,
            subtitle: String? = nil,
            action: @escaping () -> Void = {},
            @ViewBuilder content: @escaping () -> any View
        ) {
            self.content = content
            self.action = action
            self.title = title
            self.subtitle = subtitle
        }
    }
}
