//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import UIKit

extension UIImage {

    func trimmedTransparentPixels(alphaThreshold: UInt8 = 16) -> UIImage {
        guard let cgImage else { return self }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixels,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return self
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0 ..< height {
            let rowStart = y * bytesPerRow

            for x in 0 ..< width {
                let alphaIndex = rowStart + x * bytesPerPixel + 3

                guard pixels[alphaIndex] > alphaThreshold else { continue }

                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return self }
        guard minX > 0 || minY > 0 || maxX < width - 1 || maxY < height - 1 else { return self }

        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )

        guard let croppedImage = cgImage.cropping(to: cropRect) else { return self }

        return UIImage(cgImage: croppedImage, scale: scale, orientation: imageOrientation)
    }

    func opaquePixelRatio(
        sampleSize: CGSize = CGSize(width: 32, height: 32),
        alphaThreshold: UInt8 = 230
    ) -> CGFloat {
        let width = max(1, Int(sampleSize.width.rounded()))
        let height = max(1, Int(sampleSize.height.rounded()))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalPixels = width * height
        var pixels = [UInt8](repeating: 0, count: totalPixels * bytesPerPixel)

        guard let cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixels,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return 0
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var opaquePixels = 0
        var alphaIndex = 3

        while alphaIndex < pixels.count {
            if pixels[alphaIndex] >= alphaThreshold {
                opaquePixels += 1
            }

            alphaIndex += bytesPerPixel
        }

        return CGFloat(opaquePixels) / CGFloat(totalPixels)
    }

    func data(maxSize: Int? = 30_000_000) throws -> (data: Data, contentType: String) {
        let hasAlpha = cgImage.map {
            [.alphaOnly, .first, .last, .premultipliedFirst, .premultipliedLast].contains($0.alphaInfo)
        } == true

        func validate(_ data: Data) throws {
            guard let maxSize else { return }

            if data.count > maxSize {
                throw ErrorMessage(
                    "Image is too large (\(data.count.formatted(.byteCount(style: .file))) / \(maxSize.formatted(.byteCount(style: .file)))"
                )
            }
        }

        if hasAlpha, let pngData = pngData() {
            try validate(pngData)
            return (pngData, "image/png")
        } else if let jpgData = jpegData(compressionQuality: 1) {
            try validate(jpgData)
            return (jpgData, "image/jpeg")
        } else {
            throw ErrorMessage(L10n.unknownError)
        }
    }

    /// Crops tile `index` from a sheet of `tileSize`-pixel tiles laid out `columns` per row.
    ///
    /// Tiles are measured from the thumbnail size, not the sheet, since a partial sheet may be trimmed to the tiles it holds.
    func getTileImage(index: Int, columns: Int, tileSize: CGSize) -> UIImage? {
        guard index >= 0, columns > 0, let cgImage else { return nil }

        // CGImage crops in pixels, while UIImage.size is measured in points.
        let rect = CGRect(
            x: CGFloat(index % columns) * tileSize.width,
            y: CGFloat(index / columns) * tileSize.height,
            width: tileSize.width,
            height: tileSize.height
        )

        guard !rect.isEmpty,
              CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height).contains(rect),
              let tile = cgImage.cropping(to: rect)
        else { return nil }

        return UIImage(cgImage: tile, scale: scale, orientation: imageOrientation)
    }
}
