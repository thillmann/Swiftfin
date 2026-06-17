//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import JellyfinAPI
import SwiftUI

struct CinematicBackgroundView: View {

    private enum Source {
        case item(AnyPoster?)
        case selection(Proxy, initialItem: AnyPoster?)
    }

    private let showsShadowGradient: Bool
    private let showsBlur: Bool
    private let source: Source

    init(
        item: (any Poster)?,
        showsShadowGradient: Bool = false,
        showsBlur: Bool = true
    ) {
        self.showsShadowGradient = showsShadowGradient
        self.showsBlur = showsBlur
        self.source = .item(item.map { AnyPoster($0) })
    }

    init(
        viewModel: Proxy,
        initialItem: (any Poster)?,
        showsShadowGradient: Bool = false,
        showsBlur: Bool = true
    ) {
        self.showsShadowGradient = showsShadowGradient
        self.showsBlur = showsBlur
        self.source = .selection(
            viewModel,
            initialItem: initialItem.map { AnyPoster($0) }
        )
    }

    var body: some View {
        Group {
            switch source {
            case let .item(item):
                StaticBackgroundContent(
                    item: item,
                    showsShadowGradient: showsShadowGradient,
                    showsBlur: showsBlur
                )
            case let .selection(viewModel, initialItem):
                SelectionBackgroundContent(
                    viewModel: viewModel,
                    initialItem: initialItem,
                    showsShadowGradient: showsShadowGradient,
                    showsBlur: showsBlur
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private extension CinematicBackgroundView {

    struct StaticBackgroundContent: View {

        let item: AnyPoster?
        let showsShadowGradient: Bool
        let showsBlur: Bool

        @StateObject
        private var proxy: RotateContentView.Proxy = .init()

        var body: some View {
            RotateContentView(proxy: proxy)
                .overlay {
                    if showsBlur {
                        cinematicBackgroundBlur
                    }
                }
                .onAppear {
                    updateCinematicBackground(
                        for: item?._poster,
                        transition: .fade,
                        proxy: proxy
                    )
                }
                .onChange(of: item) { _, newItem in
                    updateCinematicBackground(
                        for: newItem?._poster,
                        transition: .fade,
                        proxy: proxy
                    )
                }
                .overlay {
                    if showsShadowGradient {
                        cinematicBackgroundShadowGradient
                    }
                }
        }
    }

    struct SelectionBackgroundContent: View {

        @ObservedObject
        var viewModel: Proxy

        let initialItem: AnyPoster?
        let showsShadowGradient: Bool
        let showsBlur: Bool

        @StateObject
        private var proxy: RotateContentView.Proxy = .init()

        var body: some View {
            RotateContentView(proxy: proxy)
                .overlay {
                    if showsBlur {
                        cinematicBackgroundBlur
                    }
                }
                .onAppear {
                    updateCinematicBackground(
                        for: viewModel.currentSelection?.item?._poster ?? initialItem?._poster,
                        transition: .fade,
                        proxy: proxy
                    )
                }
                .onChange(of: viewModel.currentSelection) { _, newSelection in
                    updateCinematicBackground(
                        for: newSelection?.item?._poster,
                        transition: newSelection?.transition ?? .fade,
                        proxy: proxy
                    )
                }
                .overlay {
                    if showsShadowGradient {
                        cinematicBackgroundShadowGradient
                    }
                }
        }
    }
}

private enum CinematicBackgroundImageProvider {

    static func imageSources(for item: (any Poster)?) -> [ImageSource] {
        (
            homeImageSources(for: item) +
                (item?.cinematicImageSources(maxWidth: nil) ?? []) +
                (item?.landscapeImageSources(maxWidth: nil) ?? [])
        )
        .filter { $0.url != nil }
    }

    private static func homeImageSources(for item: (any Poster)?) -> [ImageSource] {
        guard let item, let item = item as? BaseItemDto else {
            return []
        }

        let imageType: ImageType = {
            switch item.type {
            case .episode, .musicVideo, .video:
                .primary
            default:
                .backdrop
            }
        }()

        return [item.imageSource(imageType, maxWidth: 1920)]
    }
}

private var cinematicBackgroundBlur: some View {
    GeometryReader { proxy in
        BlurView(style: .dark)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(gradient: Gradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white.opacity(0.7), location: 0.4),
                        .init(color: .white.opacity(0), location: 1),
                    ]), startPoint: .bottom, endPoint: .top)
                        .frame(height: max(proxy.size.height - 150, 0))

                    Color.white
                }
            }
    }
    .allowsHitTesting(false)
}

private var cinematicBackgroundShadowGradient: some View {
    LinearGradient(
        stops: [
            .init(color: .black.opacity(0.36), location: 0),
            .init(color: .black.opacity(0.24), location: 0.28),
            .init(color: .black.opacity(0.56), location: 0.62),
            .init(color: .black.opacity(0.9), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    .allowsHitTesting(false)
}

private func updateCinematicBackground(
    for item: (any Poster)?,
    transition: RotateContentView.Transition,
    proxy: RotateContentView.Proxy
) {
    let imageSources = CinematicBackgroundImageProvider.imageSources(for: item)

    guard imageSources.isNotEmpty else {
        proxy.update(transition: transition) {
            Color.clear
        }
        return
    }

    proxy.update(transition: transition) {
        GeometryReader { geometry in
            ImageView(imageSources)
                .image { image in
                    image
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .clipped()
                }
                .placeholder { _ in
                    Color.clear
                }
                .failure {
                    Color.clear
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .clipped()
        }
    }
}

extension CinematicBackgroundView {

    class Proxy: ObservableObject {

        struct Selection: Equatable {
            let item: AnyPoster?
            let transition: RotateContentView.Transition
        }

        @Published
        var currentSelection: Selection?

        var currentItem: AnyPoster? {
            currentSelection?.item
        }

        private var cancellables = Set<AnyCancellable>()
        private var currentItemSubject = CurrentValueSubject<Selection?, Never>(nil)

        init() {
            currentItemSubject
                .debounce(for: 0.5, scheduler: DispatchQueue.main)
                .removeDuplicates()
                .sink { newSelection in
                    self.currentSelection = newSelection
                }
                .store(in: &cancellables)
        }

        func select(
            item: any Poster,
            transition: RotateContentView.Transition = .fade
        ) {
            currentItemSubject.send(
                Selection(
                    item: AnyPoster(item),
                    transition: transition
                )
            )
        }
    }
}
