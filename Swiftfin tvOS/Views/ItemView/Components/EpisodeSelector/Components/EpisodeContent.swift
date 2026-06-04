//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension SeriesEpisodeSelector {

    struct EpisodeContent: View {

        private let action: () -> Void
        private let onFocusChange: (Bool) -> Void

        let subHeader: String
        let header: String
        let content: String
        let releaseDate: String?
        let isPosterFocused: Bool

        @FocusState
        private var isFocused: Bool

        private var isHighlighted: Bool {
            isFocused || isPosterFocused
        }

        private var primaryTextColor: Color {
            .primary
        }

        private var secondaryTextColor: Color {
            .secondary
        }

        private var backgroundOpacity: Double {
            if isFocused {
                0.34
            } else if isPosterFocused {
                0.16
            } else {
                0
            }
        }

        private var posterFocusOffset: CGFloat {
            isPosterFocused && !isFocused ? 18 : 0
        }

        @ViewBuilder
        private var backgroundView: some View {
            let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

            ZStack {
                if #available(tvOS 26.0, *) {
                    shape
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: shape)
                        .opacity(isFocused ? 1 : 0)
                } else {
                    shape
                        .fill(.regularMaterial)
                        .opacity(isFocused ? 1 : 0)
                }

                shape
                    .fill(.white.opacity(backgroundOpacity))
            }
        }

        @ViewBuilder
        private var subHeaderView: some View {
            Text(subHeader)
                .font(.caption)
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
                .textCase(.uppercase)
        }

        @ViewBuilder
        private var headerView: some View {
            Text(header)
                .font(.footnote.weight(.semibold))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
                .padding(.bottom, 1)
        }

        @ViewBuilder
        private var contentView: some View {
            Text(content)
                .font(.caption.weight(.semibold))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.leading)
                .lineLimit(2, reservesSpace: true)
        }

        @ViewBuilder
        private var releaseDateView: some View {
            if let releaseDate {
                Text(releaseDate)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }
        }

        var body: some View {
            Button {
                action()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    subHeaderView

                    headerView

                    contentView
                        .frame(maxWidth: .infinity, alignment: .leading)

                    releaseDateView
                }
                .padding()
                .background {
                    backgroundView
                }
            }
            .buttonStyle(.borderless)
            .focused($isFocused)
            .focusEffectDisabled()
            .offset(y: posterFocusOffset)
            .scaleEffect(isFocused ? 1.12 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: isFocused ? 18 : 0, y: isFocused ? 10 : 0)
            .animation(.easeOut(duration: 0.18), value: isFocused)
            .animation(.easeOut(duration: 0.18), value: isPosterFocused)
            .onChange(of: isFocused) { _, newValue in
                onFocusChange(newValue)
            }
        }

        init(
            subHeader: String,
            header: String,
            content: String,
            releaseDate: String? = nil,
            isPosterFocused: Bool = false,
            onFocusChange: @escaping (Bool) -> Void = { _ in },
            action: @escaping () -> Void = {}
        ) {
            self.subHeader = subHeader
            self.header = header
            self.content = content
            self.releaseDate = releaseDate
            self.isPosterFocused = isPosterFocused
            self.onFocusChange = onFocusChange
            self.action = action
        }
    }
}
