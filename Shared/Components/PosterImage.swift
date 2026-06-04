//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import BlurHashKit
import SwiftUI

/// Retrieving images by exact pixel dimensions is a bit
/// intense for normal usage and eases cache usage and modifications.
private let landscapeMaxWidth: CGFloat = 300
private let portraitMaxWidth: CGFloat = 200

struct PosterImage<Item: Poster>: View {

    private let contentMode: ContentMode
    private let imageMaxWidth: CGFloat
    private let item: Item
    private let prefersBlurHashPlaceholder: Bool
    private let type: PosterDisplayType

    init(
        item: Item,
        type: PosterDisplayType,
        contentMode: ContentMode = .fill,
        maxWidth: CGFloat? = nil,
        prefersBlurHashPlaceholder: Bool = true
    ) {
        self.contentMode = contentMode
        self.imageMaxWidth = maxWidth ?? (type == .landscape ? landscapeMaxWidth : portraitMaxWidth)
        self.item = item
        self.prefersBlurHashPlaceholder = prefersBlurHashPlaceholder
        self.type = type
    }

    private var imageSources: [ImageSource] {
        switch type {
        case .landscape:
            item.landscapeImageSources(maxWidth: imageMaxWidth, quality: 90)
        case .portrait:
            item.portraitImageSources(maxWidth: imageMaxWidth, quality: 90)
        case .square:
            item.squareImageSources(maxWidth: imageMaxWidth, quality: 90)
        }
    }

    @ViewBuilder
    private var placeholderContent: some View {
        PosterFallbackContentView(
            title: item.showTitle ? item.displayTitle : nil,
            systemName: item.systemImage
        )
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.complexSecondary)

            AlternateLayoutView {
                Color.clear
            } content: {
                ImageView(imageSources)
                    .image(item.transform)
                    .placeholder { imageSource in
                        if prefersBlurHashPlaceholder, let blurHash = imageSource.blurHash {
                            BlurHashView(blurHash: blurHash)
                        } else {
                            placeholderContent
                        }
                    }
                    .failure {
                        placeholderContent
                    }
            }
        }
        .posterStyle(
            type,
            contentMode: contentMode
        )
    }
}

private struct PosterFallbackContentView: View {

    let title: String?
    let systemName: String?

    var body: some View {
        ZStack {
            SystemImageContentView(systemName: systemName)

            if let title {
                VStack {
                    Spacer()

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
            }
        }
    }
}
