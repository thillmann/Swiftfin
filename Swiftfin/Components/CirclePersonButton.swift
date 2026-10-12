//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct CirclePersonButton: View {

    @Namespace
    private var namespace

    let person: BaseItemPerson
    let action: (Namespace.ID) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button {
                action(namespace)
            } label: {
                GeometryReader { proxy in
                    PlatformPosterImage(
                        item: person,
                        type: .portrait,
                        imageContentMode: .fill,
                        appliesPosterStyle: false,
                        maxWidth: proxy.size.width
                    ) {
                        ZStack {
                            Color(.darkGray)

                            Text(person.displayTitle.initials)
                                .font(.system(size: proxy.size.width * 0.36, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.width)
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .backport
                    .matchedTransitionSource(id: "item", in: namespace)
                }
                .aspectRatio(1, contentMode: .fit)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(person.displayTitle)

            VStack(spacing: 2) {
                Text(person.displayTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let role = person.subtitle {
                    Text(role)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
