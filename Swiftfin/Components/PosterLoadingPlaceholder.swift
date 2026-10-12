//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

struct PosterLoadingPlaceholder: View {

    static let transitionAnimation = Animation.easeInOut(duration: 0.2)

    let type: PosterDisplayType
    let additionalHeight: CGFloat
    let systemName: String?

    init(
        type: PosterDisplayType,
        additionalHeight: CGFloat = 0,
        systemName: String? = nil
    ) {
        self.type = type
        self.additionalHeight = additionalHeight
        self.systemName = systemName
    }

    private var artwork: some View {
        Color.clear
            .posterAspectRatio(type, contentMode: .fit)
            .overlay {
                if let systemName {
                    SystemImageContentView(systemName: systemName)
                }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            artwork

            if additionalHeight > 0 {
                Color.clear
                    .frame(height: additionalHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.secondarySystemFill.opacity(0.75))
        .posterGlassStyle(type)
        .posterShadow()
        .accessibilityHidden(true)
    }
}

extension PosterLoadingPlaceholder {

    struct Labels: View {

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Loading title")
                    .font(.footnote)
                    .fontWeight(.regular)

                Text(verbatim: "Loading subtitle")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .lineLimit(1, reservesSpace: true)
            .redacted(reason: .placeholder)
            .frame(height: 34, alignment: .top)
            .accessibilityHidden(true)
        }
    }
}

struct PosterHStackLoadingPlaceholder: View {

    @Default(.Customization.showPosterLabels)
    private var showPosterLabels

    let title: String
    let type: PosterDisplayType

    private let placeholderItems: [BaseItemDto]

    init(
        title: String,
        type: PosterDisplayType,
        idPrefix: String,
        itemCount: Int = 5
    ) {
        self.title = title
        self.type = type
        self.placeholderItems = (0 ..< itemCount).map {
            BaseItemDto(id: "\(idPrefix)-loading-\($0)")
        }
    }

    var body: some View {
        PlatformPosterHStack(
            title: title,
            type: type,
            items: placeholderItems,
            headerAction: {}
        ) { _ in
            VStack(alignment: .leading, spacing: 8) {
                PosterLoadingPlaceholder(
                    type: type,
                    additionalHeight: type == .landscape ? PosterButtonLayout.landscapeFooterHeight : 0,
                    systemName: "film"
                )

                if showPosterLabels {
                    PosterLoadingPlaceholder.Labels()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
