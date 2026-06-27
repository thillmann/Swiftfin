//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import Nuke
import SwiftUI

struct CinematicItemHeroView<
    Accessory: View,
    Actions: View
>: View {

    @StoredValue(.User.itemViewAttributes)
    private var attributes

    private let logoWidth: CGFloat = 520
    private let logoHeight: CGFloat = 200
    private let titleWidth: CGFloat = 800

    let item: BaseItemDto
    let providedItemViewModel: ItemViewModel?
    let accessory: Accessory
    let actions: (ItemViewModel) -> Actions

    @StateObject
    private var fallbackItemViewModel: ItemViewModel

    @State
    private var finishedLogoURL: URL?

    init(
        item: BaseItemDto,
        itemViewModel: ItemViewModel? = nil,
        @ViewBuilder actions: @escaping (ItemViewModel) -> Actions,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.item = item
        self.providedItemViewModel = itemViewModel
        self.accessory = accessory()
        self.actions = actions
        self._fallbackItemViewModel = StateObject(wrappedValue: ItemViewModel(item: item))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            accessory
                .opacity(isAccessoryVisible ? 1 : 0)
                .allowsHitTesting(isAccessoryVisible)

            logoOrTitle

            DotHStack {
                if let typeLabel {
                    Text(typeLabel)
                }

                ForEach(genreLabels, id: \.self) { genre in
                    Text(genre)
                }
            }
            .font(.body)
            .foregroundStyle(.white.opacity(0.9))

            ItemView.OverviewView(item: item)
                .taglineLineLimit(1)
                .overviewLineLimit(3)
                .frame(maxWidth: 800, alignment: .leading)

            if showsDetails {
                detailRow
            }

            HStack(spacing: 20) {
                actions(itemViewModel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            updateFallbackItemViewModel()
        }
        .onChange(of: item) { _, _ in
            updateFallbackItemViewModel()
        }
    }

    private var itemViewModel: ItemViewModel {
        providedItemViewModel ?? fallbackItemViewModel
    }

    private var isAccessoryVisible: Bool {
        let source = defaultLogoSource(for: item)

        return source.url == nil || finishedLogoURL == source.url
    }

    private var logoOrTitle: some View {
        let source = defaultLogoSource(for: item)

        return Group {
            if source.url == nil {
                titleFallback
                    .frame(width: titleWidth, height: logoHeight, alignment: .leading)
            } else {
                CinematicLogoImageView(
                    source: source,
                    maxSize: CGSize(width: logoWidth, height: logoHeight),
                    onFinished: {
                        finishedLogoURL = source.url
                    }
                ) {
                    titleFallback
                }
            }
        }
        .id(source.url?.absoluteString ?? item.id ?? defaultTitle(for: item))
    }

    private var titleFallback: some View {
        Text(defaultTitle(for: item))
            .font(.system(size: 64, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: titleWidth, alignment: .leading)
    }

    private var detailRow: some View {
        HStack(spacing: 20) {
            DotHStack {
                switch item.type {
                case .episode:
                    if let premiereDateLabel = item.premiereDateLabel {
                        Text(premiereDateLabel)
                    }
                default:
                    if let premiereDateYear = item.premiereDateYear {
                        Text(premiereDateYear)
                    }
                }

                if let detailLabel {
                    Text(detailLabel)
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.9))

            ItemView.AttributesHStack(
                attributes: attributes,
                viewModel: itemViewModel
            )
        }
    }

    private var typeLabel: String? {
        switch item.type {
        case .series, .episode:
            L10n.tvShow
        case .movie:
            L10n.movie
        default:
            nil
        }
    }

    private var showsDetails: Bool {
        item.type != .person
    }

    private var genreLabels: [String] {
        if let genres = item.genres, genres.isNotEmpty {
            return genres
        }

        if item.type == .episode,
           let genres = itemViewModel.item.genres
        {
            return genres
        }

        return []
    }

    private var defaultDetailLabel: String? {
        if item.type == .episode, let seasonEpisodeLabel = item.seasonEpisodeLabel {
            return seasonEpisodeLabel
        }

        return item.runTimeLabel
    }

    private var detailLabel: String? {
        itemViewModel.playButtonItem?.runTimeLabel ?? defaultDetailLabel
    }

    private func defaultLogoSource(for item: BaseItemDto) -> ImageSource {
        if item.type == .episode {
            return item.seriesImageSource(
                .logo,
                maxWidth: logoWidth,
                maxHeight: logoHeight
            )
        }

        return item.imageSource(
            .logo,
            maxWidth: logoWidth,
            maxHeight: logoHeight
        )
    }

    private func defaultTitle(for item: BaseItemDto) -> String {
        if item.type == .episode, let seriesName = item.seriesName {
            return seriesName
        }

        return item.displayTitle
    }

    private func updateFallbackItemViewModel() {
        guard providedItemViewModel == nil else { return }

        fallbackItemViewModel.send(.replace(item))
    }
}

private struct CinematicLogoImageView<Failure: View>: View {

    let source: ImageSource
    let maxSize: CGSize
    let onFinished: () -> Void
    @ViewBuilder
    let failure: Failure

    @State
    private var image: UIImage?
    @State
    private var didFail = false

    var body: some View {
        Group {
            if let image {
                let size = displaySize(for: image.size)

                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height, alignment: .bottomLeading)
            } else if didFail {
                failure
            } else {
                Color.clear
                    .frame(width: maxSize.width, height: maxSize.height)
            }
        }
        .frame(maxWidth: maxSize.width, alignment: .bottomLeading)
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
            image = source.trimsTransparentPixels ? loadedImage.trimmedTransparentPixels() : loadedImage
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

extension CinematicItemHeroView where Accessory == EmptyView {

    init(
        item: BaseItemDto,
        itemViewModel: ItemViewModel? = nil,
        @ViewBuilder actions: @escaping (ItemViewModel) -> Actions
    ) {
        self.init(
            item: item,
            itemViewModel: itemViewModel,
            actions: actions
        ) {
            EmptyView()
        }
    }
}
