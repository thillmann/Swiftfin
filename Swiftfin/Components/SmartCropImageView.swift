//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Nuke
import SwiftUI
import UIKit
import Vision

/// Displays an image cropped around its most visually important content.
///
/// The crop is cached by image URL, target aspect ratio, and strategy. The
/// source image remains the responsibility of the caller, so item-specific
/// artwork selection stays outside this view.
struct SmartCropImageView: View {

    enum Strategy: Hashable {
        case attentionWithFaceProtection
    }

    let source: ImageSource
    let targetAspectRatio: CGFloat
    let strategy: Strategy

    @State
    private var image: UIImage?

    init(
        _ source: ImageSource,
        targetAspectRatio: CGFloat,
        strategy: Strategy = .attentionWithFaceProtection
    ) {
        self.source = source
        self.targetAspectRatio = targetAspectRatio
        self.strategy = strategy
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                DefaultPlaceholderView(blurHash: source.blurHash)
            }
        }
        .task(id: cacheKey) {
            await loadImage()
        }
    }

    private var cacheKey: SmartCropCache.Key? {
        guard let url = source.url, targetAspectRatio > 0 else { return nil }

        return .init(
            url: url,
            targetAspectRatio: targetAspectRatio,
            strategy: strategy
        )
    }

    @MainActor
    private func loadImage() async {
        image = nil

        guard let url = source.url,
              let cacheKey
        else {
            return
        }

        do {
            let sourceImage = try await ImagePipeline.shared.image(for: ImageRequest(url: url))

            guard !Task.isCancelled, let cgImage = sourceImage.cgImage else {
                return
            }

            let crop = await SmartCropCache.shared.crop(
                for: cgImage,
                key: cacheKey
            )

            guard !Task.isCancelled else { return }

            image = croppedImage(from: cgImage, crop: crop, scale: sourceImage.scale)
        } catch {
            // Keep the same empty fallback behavior as ImageView.
        }
    }

    private func croppedImage(from image: CGImage, crop: CGRect, scale: CGFloat) -> UIImage {
        let imageRect = CGRect(
            x: crop.minX * CGFloat(image.width),
            y: 0,
            width: crop.width * CGFloat(image.width),
            height: CGFloat(image.height)
        ).integral

        guard let croppedImage = image.cropping(to: imageRect) else {
            return UIImage(cgImage: image, scale: scale, orientation: .up)
        }

        return UIImage(cgImage: croppedImage, scale: scale, orientation: .up)
    }
}

private final class SmartCropCache: @unchecked Sendable {

    struct Key: Hashable {
        let url: URL
        let targetAspectRatio: CGFloat
        let strategy: SmartCropImageView.Strategy

        var cacheKey: NSString {
            let formattedAspectRatio = String(
                format: "%.3f",
                locale: Locale(identifier: "en_US_POSIX"),
                targetAspectRatio
            )
            return "\(url.absoluteString)-\(formattedAspectRatio)-\(strategy)" as NSString
        }
    }

    static let shared = SmartCropCache()

    private let cache = NSCache<NSString, CropValue>()

    func crop(for image: CGImage, key: Key) async -> CGRect {
        if let cachedCrop = cache.object(forKey: key.cacheKey) {
            return cachedCrop.rect
        }

        let crop = await SmartCropAnalyzer.crop(
            image,
            targetAspectRatio: key.targetAspectRatio,
            strategy: key.strategy
        )

        cache.setObject(CropValue(crop), forKey: key.cacheKey)
        return crop
    }

    private final class CropValue {
        let rect: CGRect

        init(_ rect: CGRect) {
            self.rect = rect
        }
    }
}

private enum SmartCropAnalyzer {

    private struct InterestRegion {
        let rect: CGRect
        let weight: CGFloat
    }

    static func crop(
        _ image: CGImage,
        targetAspectRatio: CGFloat,
        strategy: SmartCropImageView.Strategy
    ) async -> CGRect {
        let sourceAspectRatio = CGFloat(image.width) / CGFloat(image.height)
        guard sourceAspectRatio > targetAspectRatio, targetAspectRatio > 0 else {
            return .unit
        }

        let cropWidth = targetAspectRatio / sourceAspectRatio

        // A saliency model failure must not discard a usable face detection.
        // This matters on devices where one Vision model is unavailable.
        let facesResult = try? await DetectFaceRectanglesRequest().perform(on: image)
        let saliencyResult = try? await GenerateAttentionBasedSaliencyImageRequest().perform(on: image)
        return bestCrop(
            for: interestRegions(
                saliency: saliencyResult,
                faces: facesResult ?? [],
                strategy: strategy
            ),
            cropWidth: cropWidth
        )
    }

    private static func interestRegions(
        saliency: SaliencyImageObservation?,
        faces: [FaceObservation],
        strategy: SmartCropImageView.Strategy
    ) -> [InterestRegion] {
        let salientRegions = (saliency?.salientObjects ?? []).map { observation in
            InterestRegion(
                rect: observation.boundingBox.cgRect,
                weight: max(CGFloat(observation.confidence), 0.1)
            )
        }

        switch strategy {
        case .attentionWithFaceProtection:
            let faceRegions = faces.map { face in
                InterestRegion(
                    rect: face.boundingBox.cgRect,
                    weight: max(CGFloat(face.confidence), 0.1) * 3
                )
            }

            return salientRegions + faceRegions
        }
    }

    private static func bestCrop(for regions: [InterestRegion], cropWidth: CGFloat) -> CGRect {
        guard regions.isNotEmpty else {
            return centeredCrop(width: cropWidth)
        }

        let candidateOrigins = Set(
            regions.flatMap { region in
                [
                    region.rect.minX,
                    region.rect.midX - cropWidth / 2,
                    region.rect.maxX - cropWidth,
                ]
            } + [0, (1 - cropWidth) / 2, 1 - cropWidth]
        )
        .map { min(max($0, 0), 1 - cropWidth) }

        let bestOrigin = candidateOrigins.max { lhs, rhs in
            score(origin: lhs, regions: regions, cropWidth: cropWidth) <
                score(origin: rhs, regions: regions, cropWidth: cropWidth)
        } ?? (1 - cropWidth) / 2

        return CGRect(x: bestOrigin, y: 0, width: cropWidth, height: 1)
    }

    private static func score(origin: CGFloat, regions: [InterestRegion], cropWidth: CGFloat) -> CGFloat {
        let crop = CGRect(x: origin, y: 0, width: cropWidth, height: 1)

        return regions.reduce(0) { score, region in
            let visibleArea = crop.intersection(region.rect).area
            let regionArea = region.rect.area

            guard regionArea > 0 else { return score }

            return score + region.weight * visibleArea / regionArea
        }
    }

    private static func centeredCrop(width: CGFloat) -> CGRect {
        CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
    }
}

private extension CGRect {

    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    var area: CGFloat {
        width * height
    }
}
