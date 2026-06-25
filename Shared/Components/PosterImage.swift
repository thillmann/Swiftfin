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

struct PosterImage<Item: Poster, Fallback: View>: View {

    private let contentMode: ContentMode
    private let imageMaxWidth: CGFloat
    private let imageSourcesOverride: [ImageSource]?
    private let item: Item
    private let type: PosterDisplayType
    private let fallback: () -> Fallback

    init(
        item: Item,
        type: PosterDisplayType,
        contentMode: ContentMode = .fill,
        maxWidth: CGFloat? = nil,
        imageSources: [ImageSource]? = nil,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.contentMode = contentMode
        self.imageMaxWidth = maxWidth ?? (type == .landscape ? landscapeMaxWidth : portraitMaxWidth)
        self.imageSourcesOverride = imageSources
        self.item = item
        self.type = type
        self.fallback = fallback
    }

    private var imageSources: [ImageSource] {
        if let imageSourcesOverride {
            return imageSourcesOverride
        }

        return switch type {
        case .landscape:
            item.landscapeImageSources(maxWidth: imageMaxWidth, quality: 90)
        case .portrait:
            item.portraitImageSources(maxWidth: imageMaxWidth, quality: 90)
        case .square:
            item.squareImageSources(maxWidth: imageMaxWidth, quality: 90)
        }
    }

    @ViewBuilder
    private func placeholderContent(for imageSource: ImageSource) -> some View {
        if let blurHash = imageSource.blurHash {
            BlurHashView(blurHash: blurHash)
        } else {
            PosterFallbackContentView(
                title: nil,
                systemName: item.systemImage
            )
        }
    }

    @ViewBuilder
    private var fallbackContent: some View {
        fallback()
    }

    var body: some View {
        ImageView(imageSources)
            .image(item.transform)
            .placeholder { imageSource in
                placeholderContent(for: imageSource)
            }
            .failure {
                fallbackContent
            }
            .posterStyle(
                type,
                contentMode: contentMode
            )
    }
}

extension PosterImage where Fallback == PosterFallbackContentView {

    init(
        item: Item,
        type: PosterDisplayType,
        contentMode: ContentMode = .fill,
        maxWidth: CGFloat? = nil,
        imageSources: [ImageSource]? = nil
    ) {
        self.init(
            item: item,
            type: type,
            contentMode: contentMode,
            maxWidth: maxWidth,
            imageSources: imageSources
        ) {
            PosterFallbackContentView(
                title: item.showTitle ? nil : item.displayTitle,
                systemName: item.systemImage
            )
        }
    }
}

struct PosterFallbackContentView: View {

    let title: String?
    let systemName: String?

    var body: some View {
        ZStack {
            Color(.darkGray)

            SystemImageContentView(systemName: systemName)

            if let title {
                VStack {
                    Spacer()

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
        }
    }
}
