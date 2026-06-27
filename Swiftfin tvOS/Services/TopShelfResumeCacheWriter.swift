//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import TVServices
import UIKit

@MainActor
enum TopShelfResumeCacheWriter {

    private struct ArtworkRequest {
        let entry: TopShelfResumeCache.Entry
        let backdropURL: URL?
        let logoURL: URL?
    }

    private static var artworkTask: Task<Void, Never>?

    static func write(items: [BaseItemDto], userSession: UserSession) {
        let requests = items
            .prefix(8)
            .compactMap { artworkRequest(for: $0, userSession: userSession) }
        let entries = requests.map(\.entry)

        TopShelfResumeCache.write(entries: entries)
        TVTopShelfContentProvider.topShelfContentDidChange()

        artworkTask?.cancel()
        artworkTask = Task {
            var renderedEntries = entries

            for (index, request) in requests.enumerated() {
                guard !Task.isCancelled else { return }

                if let imageURL = await renderArtwork(for: request) {
                    renderedEntries[index] = request.entry.replacingImageURL(with: imageURL)

                    if index == 0 {
                        TopShelfResumeCache.write(entries: renderedEntries)
                        TVTopShelfContentProvider.topShelfContentDidChange()
                    }
                }
            }

            guard !Task.isCancelled else { return }
            TopShelfResumeCache.write(entries: renderedEntries)
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    }

    private static func artworkRequest(
        for item: BaseItemDto,
        userSession: UserSession
    ) -> ArtworkRequest? {
        guard let itemID = item.id else { return nil }

        let backdropURL = imageURL(for: item, userSession: userSession)
        let displayItemID = item.type == .episode ? item.seriesID ?? itemID : itemID

        return ArtworkRequest(
            entry: TopShelfResumeCache.Entry(
                id: itemID,
                title: title(for: item),
                contextTitle: L10n.resume,
                summary: item.overview,
                genre: item.genres?.prefix(2).joined(separator: ", "),
                duration: item.runTimeTicks.map { TimeInterval($0) / 10_000_000 },
                creationDate: item.premiereDate,
                imageURL: backdropURL,
                displayURL: actionURL(userID: userSession.user.id, itemID: displayItemID, action: "display"),
                playURL: actionURL(userID: userSession.user.id, itemID: itemID, action: "play")
            ),
            backdropURL: backdropURL,
            logoURL: logoURL(for: item, userSession: userSession)
        )
    }

    private static func title(for item: BaseItemDto) -> String {
        if item.type == .episode, let seriesName = item.seriesName {
            return seriesName
        }

        return item.name ?? L10n.unknown
    }

    private static func imageURL(
        for item: BaseItemDto,
        userSession: UserSession
    ) -> URL? {
        if item.type == .episode, let seriesID = item.seriesID {
            return itemImageURL(
                itemID: item.id,
                imageType: .primary,
                tag: item.imageTags?[ImageType.primary.rawValue],
                requireTag: true,
                userSession: userSession
            ) ?? itemImageURL(
                itemID: seriesID,
                imageType: .backdrop,
                tag: nil,
                requireTag: false,
                userSession: userSession
            ) ?? itemImageURL(
                itemID: seriesID,
                imageType: .thumb,
                tag: nil,
                requireTag: false,
                userSession: userSession
            )
        }

        return itemImageURL(
            itemID: item.id,
            imageType: .backdrop,
            tag: item.backdropImageTags?.first,
            requireTag: true,
            userSession: userSession
        ) ?? itemImageURL(
            itemID: item.id,
            imageType: .thumb,
            tag: item.imageTags?[ImageType.thumb.rawValue],
            requireTag: true,
            userSession: userSession
        ) ?? itemImageURL(
            itemID: item.id,
            imageType: .primary,
            tag: item.imageTags?[ImageType.primary.rawValue],
            requireTag: true,
            userSession: userSession
        )
    }

    private static func logoURL(
        for item: BaseItemDto,
        userSession: UserSession
    ) -> URL? {
        if item.type == .episode, let seriesID = item.seriesID {
            return itemImageURL(
                itemID: seriesID,
                imageType: .logo,
                tag: nil,
                requireTag: false,
                userSession: userSession
            )
        }

        return itemImageURL(
            itemID: item.id,
            imageType: .logo,
            tag: item.imageTags?[ImageType.logo.rawValue],
            requireTag: true,
            userSession: userSession
        )
    }

    private static func itemImageURL(
        itemID: String?,
        imageType: ImageType,
        tag: String?,
        requireTag: Bool,
        userSession: UserSession
    ) -> URL? {
        guard let itemID, tag != nil || !requireTag else { return nil }

        let parameters = Paths.GetItemImageParameters(
            maxWidth: 1920,
            maxHeight: 1080,
            quality: 90,
            tag: tag,
            format: imageType == .logo ? .png : nil,
            imageIndex: nil
        )

        let request = Paths.getItemImage(
            itemID: itemID,
            imageType: imageType.rawValue,
            parameters: parameters
        )

        return userSession.client.url(with: request, queryAPIKey: true)
    }

    private static func actionURL(
        userID: String,
        itemID: String,
        action: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "jellyfin"
        components.host = "users"
        components.path = "/\(userID)/items/\(itemID)"
        components.queryItems = [
            URLQueryItem(name: "action", value: action),
        ]

        return components.url
    }

    private static func renderArtwork(for request: ArtworkRequest) async -> URL? {
        guard let destinationURL = TopShelfResumeCache.artworkURL(for: request.entry.id) else {
            return nil
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        guard let backdropURL = request.backdropURL,
              let backdrop = await loadImage(from: backdropURL)
        else {
            return nil
        }

        let logo = await request.logoURL.asyncFlatMap(loadImage)?.trimmedTransparentPixels()
        let size = CGSize(width: 1920, height: 1080)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 2

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            backdrop.drawAspectFill(in: CGRect(origin: .zero, size: size))

            if let logo {
                logo.drawAspectFit(in: CGRect(x: 120, y: 100, width: 520, height: 200))
            }
        }

        guard let data = image.jpegData(compressionQuality: 0.95) else { return nil }

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: .atomic)
            return destinationURL
        } catch {
            return nil
        }
    }

    private static func loadImage(from url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            return nil
        }

        return UIImage(data: data)
    }
}

private extension TopShelfResumeCache.Entry {

    func replacingImageURL(with imageURL: URL) -> Self {
        .init(
            id: id,
            title: title,
            contextTitle: contextTitle,
            summary: summary,
            genre: genre,
            duration: duration,
            creationDate: creationDate,
            imageURL: imageURL,
            displayURL: displayURL,
            playURL: playURL
        )
    }
}

private extension Optional {

    func asyncFlatMap<NewValue>(
        _ transform: (Wrapped) async -> NewValue?
    ) async -> NewValue? {
        guard let self else { return nil }
        return await transform(self)
    }
}

private extension UIImage {

    func drawAspectFill(in rect: CGRect) {
        let scale = max(rect.width / size.width, rect.height / size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        draw(in: drawRect)
    }

    func drawAspectFit(in rect: CGRect) {
        let scale = min(rect.width / size.width, rect.height / size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let drawRect = CGRect(
            x: rect.minX,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        draw(in: drawRect)
    }
}
