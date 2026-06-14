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

extension ProgramsView {

    struct ProgramOverlay: View {
        @Environment(\.isFocused)
        private var isFocused

        let program: BaseItemDto
        let channel: BaseItemDto?

        @ViewBuilder
        var channelIcon: some View {
            if let channel {
                ProgramChannelIcon(imageSources: channel.squareImageSources(maxWidth: 42, quality: 60))
            }
        }

        @ViewBuilder
        var progress: some View {
            if let progress = program.programProgress, progress >= 0, progress <= 1 {
                ProgressView(value: progress)
                    .progressViewStyle(
                        FeatureInlineProgressStyle(
                            trackColor: .white.opacity(0.2),
                            fillColor: .white.opacity(1)
                        )
                    )
                    .frame(width: 40)
            }
        }

        var displayTitle: some View {
            Text(program.displayTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }

        @ViewBuilder
        private var bottomBackdrop: some View {
            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.34),
                    .black.opacity(0.5),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            colors: [
                                .clear,
                                .black.opacity(0.85),
                                .black,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }

        var body: some View {
            ZStack {
                VStack {
                    HStack {
                        channelIcon

                        Spacer(minLength: 0)
                    }
                    .padding(16)

                    Spacer(minLength: 0)

                    ZStack(alignment: .bottom) {
                        bottomBackdrop

                        HStack(alignment: .center, spacing: 12) {
                            progress

                            displayTitle

                            Spacer(minLength: 0)
                        }
                        .padding(16)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isFocused ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }

    private struct ProgramChannelIcon: View {

        @MainActor
        private static let standaloneArtworkCache = NSCache<NSString, NSNumber>()

        @State
        private var usesStandaloneArtwork = false

        let imageSources: [ImageSource]

        private var imageURL: URL? {
            imageSources.first?.url
        }

        private var imageDimension: CGFloat {
            usesStandaloneArtwork ? 42 : 40
        }

        var body: some View {
            ZStack {
                if !usesStandaloneArtwork {
                    Circle()
                        .fill(.thinMaterial)
                }

                ImageView(imageSources)
                    .image {
                        $0.aspectRatio(contentMode: .fit)
                    }
                    .failure { EmptyView() }
                    .placeholder { _ in EmptyView() }
                    .frame(width: imageDimension, height: imageDimension)
                    .clipped()
            }
            .frame(width: 50, height: 50)
            .task(id: imageURL) {
                await updateArtworkTreatment()
            }
        }

        @MainActor
        private func updateArtworkTreatment() async {
            guard let imageURL else {
                usesStandaloneArtwork = false
                return
            }

            let cacheKey = imageURL.absoluteString as NSString

            if let cachedValue = Self.standaloneArtworkCache.object(forKey: cacheKey) {
                usesStandaloneArtwork = cachedValue.boolValue
                return
            }

            usesStandaloneArtwork = false

            do {
                let image = try await ImagePipeline.shared.image(for: imageURL)
                let standaloneArtwork = image.opaquePixelRatio() > 0.72

                Self.standaloneArtworkCache.setObject(NSNumber(value: standaloneArtwork), forKey: cacheKey)
                usesStandaloneArtwork = standaloneArtwork
            } catch {
                usesStandaloneArtwork = false
            }
        }
    }

    struct ProgramFallback: View {
        @Environment(\.isFocused)
        private var isFocused

        var body: some View {
            Image(systemName: "tv")
                .font(.largeTitle)
                .foregroundStyle(.white)
                .opacity(isFocused ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }
}
