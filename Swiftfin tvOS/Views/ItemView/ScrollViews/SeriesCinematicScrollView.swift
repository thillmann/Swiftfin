//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

private let seriesCinematicScrollCoordinateSpace = "series-cinematic-scroll"

extension ItemView {

    struct SeriesCinematicScrollView<Content: View>: ScrollContainerView {

        @ObservedObject
        private var viewModel: ItemViewModel

        @StateObject
        private var focusGuide = FocusGuide()
        @StateObject
        private var choreography = SeriesScrollChoreographyModel()

        private let content: Content

        init(
            viewModel: ItemViewModel,
            content: @escaping () -> Content
        ) {
            self.viewModel = viewModel
            self.content = content()
        }

        private func withBackgroundImageSource(
            @ViewBuilder content: @escaping (ImageSource) -> some View
        ) -> some View {
            let imageSource = viewModel.item.imageSource(.backdrop, maxWidth: 1920)

            return content(imageSource)
                .id(imageSource.url?.hashValue)
                .animation(.linear(duration: 0.1), value: imageSource.url?.hashValue)
        }

        var body: some View {
            GeometryReader { proxy in
                ZStack {
                    withBackgroundImageSource { imageSource in
                        ImageView(imageSource)
                            .overlay {
                                BlurView(style: .dark)
                                    .opacity(choreography.backdropBlurOpacity)
                            }
                            .overlay(Color.black.opacity(0.2 + choreography.backdropDimOpacity))
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        content
                            .environmentObject(focusGuide)
                            .environmentObject(choreography)
                    }
                    .coordinateSpace(name: seriesCinematicScrollCoordinateSpace)
                }
                .onPreferenceChange(SeriesEpisodeRailMinYPreferenceKey.self) { newValue in
                    choreography.update(
                        railMinY: newValue,
                        viewportHeight: proxy.size.height
                    )
                }
            }
            .ignoresSafeArea()
        }
    }
}

final class SeriesScrollChoreographyModel: ObservableObject {

    @Published
    private(set) var progress: CGFloat = 0

    var backdropBlurOpacity: CGFloat {
        progress * 0.95
    }

    var backdropDimOpacity: CGFloat {
        progress * 0.35
    }

    var centeredLogoOpacity: CGFloat {
        clamp((progress - 0.08) / 0.72, min: 0, max: 1)
    }

    var centeredLogoParallaxOffset: CGFloat {
        (1 - progress) * 34 - progress * 10
    }

    var seasonPillOpacity: CGFloat {
        clamp((progress - 0.2) / 0.55, min: 0, max: 1)
    }

    var seasonPillOffset: CGFloat {
        (1 - progress) * 26
    }

    var lowerContentDelayedOffset: CGFloat {
        let delayedProgress = clamp((progress - 0.28) / 0.72, min: 0, max: 1)
        return (1 - delayedProgress) * 64
    }

    func update(railMinY: CGFloat, viewportHeight: CGFloat) {
        guard railMinY.isFinite, viewportHeight > 0 else { return }

        let heroFocusedY = viewportHeight * 0.78
        let contentFocusedY = viewportHeight * 0.42
        let denominator = heroFocusedY - contentFocusedY
        guard denominator > 0 else { return }

        let next = clamp((heroFocusedY - railMinY) / denominator, min: 0, max: 1)

        guard abs(next - progress) > 0.001 else { return }

        withAnimation(.linear(duration: 0.12)) {
            progress = next
        }
    }
}

private struct SeriesEpisodeRailMinYPreferenceKey: PreferenceKey {

    static let defaultValue: CGFloat = .infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func seriesEpisodeRailAnchor() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: SeriesEpisodeRailMinYPreferenceKey.self,
                        value: proxy.frame(in: .named(seriesCinematicScrollCoordinateSpace)).minY
                    )
            }
        }
    }
}
