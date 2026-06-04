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

    @ObservedObject
    var viewModel: Proxy

    @StateObject
    private var proxy: RotateContentView.Proxy = .init()

    var initialItem: (any Poster)?

    var body: some View {
        RotateContentView(proxy: proxy)
            .overlay {
                bottomBlur
            }
            .onAppear {
                updateBackground(for: viewModel.currentItem?._poster ?? initialItem)
            }
            .onChange(of: viewModel.currentItem) { _, newItem in
                updateBackground(for: newItem?._poster)
            }
    }

    private var bottomBlur: some View {
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

    private func updateBackground(for item: (any Poster)?) {
        let imageSources = (
            homeImageSources(for: item) +
                (item?.cinematicImageSources(maxWidth: nil) ?? []) +
                (item?.landscapeImageSources(maxWidth: nil) ?? [])
        )
        .filter { $0.url != nil }

        guard imageSources.isNotEmpty else {
            proxy.update {
                Color.clear
            }
            return
        }

        proxy.update {
            ImageView(imageSources)
                .placeholder { _ in
                    Color.clear
                }
                .failure {
                    Color.clear
                }
                .aspectRatio(contentMode: .fill)
        }
    }

    private func homeImageSources(for item: (any Poster)?) -> [ImageSource] {
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

    class Proxy: ObservableObject {

        @Published
        var currentItem: AnyPoster?

        private var cancellables = Set<AnyCancellable>()
        private var currentItemSubject = CurrentValueSubject<AnyPoster?, Never>(nil)

        init() {
            currentItemSubject
                .debounce(for: 0.5, scheduler: DispatchQueue.main)
                .removeDuplicates()
                .sink { newItem in
                    self.currentItem = newItem
                }
                .store(in: &cancellables)
        }

        func select(item: any Poster) {
            currentItemSubject.send(AnyPoster(item))
        }
    }
}
