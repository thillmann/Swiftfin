//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

enum CirclePosterButtonDefaults {
    static let labelSpacing: CGFloat = 10
    static let rowAspectRatio: CGFloat = 0.75
    static let focusAnimation = Animation.easeInOut(duration: 0.18)
}

protocol CirclePosterRepresentable: Poster {
    var circlePoster: AnyPoster { get }
}

struct CirclePosterButton<Item: CirclePosterRepresentable>: View {
    @FocusState
    private var isFocused: Bool

    let item: Item
    let title: String
    let subtitle: String?
    let action: () -> Void

    init(
        item: Item,
        title: String? = nil,
        subtitle: String? = nil,
        action: @escaping () -> Void
    ) {
        self.item = item
        self.title = title ?? item.displayTitle
        self.subtitle = subtitle ?? item.subtitle
        self.action = action
    }

    private func posterButton(length: CGFloat) -> some View {
        Button(action: action) {
            PosterImage(
                item: item.circlePoster,
                type: .square,
                maxWidth: length
            )
            .frame(maxWidth: length, maxHeight: length)
        }
        .buttonStyle(.card)
        .buttonBorderShape(.circle)
        .contentShape(.contextMenuPreview, Circle())
        .containerShape(.circle)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: CirclePosterButtonDefaults.labelSpacing) {
                posterButton(length: proxy.size.width)
                    .focused($isFocused)
                    .accessibilityLabel(title)
                    .matchedContextMenu(for: item)

                CirclePosterLabel(
                    title: title,
                    subtitle: subtitle,
                    isFocused: isFocused
                )
            }
            .animation(CirclePosterButtonDefaults.focusAnimation, value: isFocused)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }
}

private struct CirclePosterLabel: View {
    let title: String
    let subtitle: String?
    let isFocused: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1, reservesSpace: true)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.white)
                    .opacity(isFocused ? 1 : 0.6)
                    .lineLimit(1, reservesSpace: true)
            }
        }
        .animation(CirclePosterButtonDefaults.focusAnimation, value: isFocused)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

extension BaseItemDto: CirclePosterRepresentable {

    var circlePoster: AnyPoster {
        AnyPoster(CircleChannelPoster(channel: self))
    }
}

extension BaseItemPerson: CirclePosterRepresentable {

    var circlePoster: AnyPoster {
        AnyPoster(CirclePersonPoster(person: self))
    }
}

extension UnifiedSearchResult: CirclePosterRepresentable {

    var circlePoster: AnyPoster {
        AnyPoster(CircleSearchResultPoster(item: self))
    }
}

private struct CircleChannelPoster: Poster {

    let channel: BaseItemDto

    var id: String {
        channel.id ?? ""
    }

    var unwrappedIDHashOrZero: Int {
        channel.unwrappedIDHashOrZero
    }

    var displayTitle: String {
        channel.displayTitle
    }

    var preferredPosterDisplayType: PosterDisplayType {
        .square
    }

    var showTitle: Bool {
        false
    }

    var systemImage: String {
        channel.systemImage
    }

    func squareImageSources(maxWidth: CGFloat?, quality: Int?) -> [ImageSource] {
        channel.squareImageSources(maxWidth: maxWidth, quality: quality)
            .appending(channel.portraitImageSources(maxWidth: maxWidth, quality: quality))
    }

    func transform(image: Image) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(18)
    }
}

private struct CirclePersonPoster: Poster {

    let person: BaseItemPerson

    var id: String {
        person.id ?? ""
    }

    var unwrappedIDHashOrZero: Int {
        person.unwrappedIDHashOrZero
    }

    var displayTitle: String {
        person.displayTitle
    }

    var preferredPosterDisplayType: PosterDisplayType {
        .square
    }

    var subtitle: String? {
        person.subtitle
    }

    var showTitle: Bool {
        false
    }

    var systemImage: String {
        person.systemImage
    }

    func squareImageSources(maxWidth: CGFloat?, quality: Int?) -> [ImageSource] {
        person.portraitImageSources(maxWidth: maxWidth, quality: quality)
    }

    func transform(image: Image) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}

private struct CircleSearchResultPoster: Poster {

    let item: UnifiedSearchResult

    var id: String {
        item.id
    }

    var unwrappedIDHashOrZero: Int {
        item.unwrappedIDHashOrZero
    }

    var displayTitle: String {
        item.displayTitle
    }

    var preferredPosterDisplayType: PosterDisplayType {
        .square
    }

    var showTitle: Bool {
        false
    }

    var systemImage: String {
        item.systemImage
    }

    func squareImageSources(maxWidth: CGFloat?, quality: Int?) -> [ImageSource] {
        item.squareImageSources(maxWidth: maxWidth, quality: quality)
    }

    func transform(image: Image) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}
