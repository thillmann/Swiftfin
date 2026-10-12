//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Nuke
import SwiftUI
import UIKit

/// Loads and sizes cinematic logos from their decoded image dimensions.
struct CinematicLogoImageView<Failure: View>: View {

    let source: ImageSource
    let maxSize: CGSize
    let alignment: Alignment
    let trimsTransparentPixels: Bool
    let onFinished: () -> Void
    @ViewBuilder
    let failure: Failure

    @State
    private var image: UIImage?
    @State
    private var didFail = false

    init(
        source: ImageSource,
        maxSize: CGSize,
        alignment: Alignment = .bottomLeading,
        trimsTransparentPixels: Bool? = nil,
        onFinished: @escaping () -> Void = {},
        @ViewBuilder failure: () -> Failure
    ) {
        self.source = source
        self.maxSize = maxSize
        self.alignment = alignment
        self.trimsTransparentPixels = trimsTransparentPixels ?? source.trimsTransparentPixels
        self.onFinished = onFinished
        self.failure = failure()
    }

    var body: some View {
        Group {
            if let image {
                let size = displaySize(for: image.size)

                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height, alignment: alignment)
            } else if didFail {
                failure
            } else {
                Color.clear
                    .frame(width: maxSize.width, height: maxSize.height)
            }
        }
        .frame(maxWidth: maxSize.width, alignment: alignment)
        .task(id: source) {
            await loadImage()
        }
    }

    private var imageRequest: ImageRequest? {
        guard let url = source.url else { return nil }

        return ImageRequest(url: url)
    }

    @MainActor
    private func loadImage() async {
        image = nil
        didFail = false

        guard let imageRequest else {
            didFail = true
            onFinished()
            return
        }

        do {
            let loadedImage = try await ImagePipeline.shared.image(for: imageRequest)
            image = trimsTransparentPixels ? loadedImage.trimmedTransparentPixels() : loadedImage
            onFinished()
        } catch {
            didFail = true
            onFinished()
        }
    }

    private func displaySize(for imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return maxSize
        }

        let scale = min(
            maxSize.width / imageSize.width,
            maxSize.height / imageSize.height
        )

        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }
}
