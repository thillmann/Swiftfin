//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct AttributeBadge: View {

    @Environment(\.font)
    private var font

    enum Style {
        case fill
        case outline
    }

    private let style: Style
    private let content: () -> any View

    private var usedFont: Font {
        font ?? .caption2.weight(.semibold)
    }

    @ViewBuilder
    private var innerBody: some View {
        if style == .fill {
            content()
                .eraseToAnyView()
                .padding(.init(vertical: 1, horizontal: 4))
                .hidden()
                .background {
                    Color(.white.opacity(0.8))
                        .cornerRadius(4)
                        .inverseMask {
                            content()
                                .eraseToAnyView()
                                .padding(.init(vertical: 1, horizontal: 4))
                        }
                }
        } else {
            content()
                .eraseToAnyView()
                .foregroundStyle(.white.opacity(0.8))
                .padding(.init(vertical: 1, horizontal: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.white.opacity(0.8), lineWidth: 2)
                )
        }
    }

    var body: some View {
        innerBody
            .labelStyle(AttributeBadgeLabelStyle())
            .font(usedFont)
    }
}

extension AttributeBadge {

    init(
        style: Style,
        title: @autoclosure @escaping () -> Text
    ) {
        self.init(style: style) {
            title()
        }
    }

    init(
        style: Style,
        title: String
    ) {
        self.init(style: style) {
            Text(title)
        }
    }

    init(
        style: Style,
        title: String,
        image: Image
    ) {
        self.style = style
        self.content = {
            Label { Text(title) } icon: { image }
        }
    }

    init(
        style: Style,
        title: String,
        image: @escaping () -> Image
    ) {
        self.style = style
        self.content = {
            Label { Text(title) } icon: { image() }
        }
    }

    init(
        style: Style,
        title: String,
        systemName: String
    ) {
        self.style = style
        self.content = {
            Label { Text(title) } icon: { Image(systemName: systemName) }
        }
    }

    init(
        style: Style,
        title: Text,
        image: Image
    ) {
        self.style = style
        self.content = {
            Label { title } icon: { image }
        }
    }

    init(
        style: Style,
        title: Text,
        image: @escaping () -> Image
    ) {
        self.style = style
        self.content = {
            Label { title } icon: { image() }
        }
    }

    init(
        style: Style,
        title: Text,
        systemName: String
    ) {
        self.style = style
        self.content = {
            Label { title } icon: { Image(systemName: systemName) }
        }
    }
}

private struct AttributeBadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.scaleEffect(0.8)

            configuration.title
        }
    }
}
