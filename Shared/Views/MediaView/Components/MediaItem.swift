//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

// Note: the design reason to not have a local label always on top
//       is to have the same failure/empty color for all views

extension MediaView {

    // TODO: custom view for folders and tv (allow customization?)
    //       - differentiate between what media types are Swiftfin only
    //         which would allow some cleanup
    //       - allow server or random view per library?
    // TODO: if local label on image, also needs to be in blurhash placeholder
    struct MediaItem: View {

        @Default(.Customization.Library.randomImage)
        private var useRandomImage

        @ObservedObject
        var viewModel: MediaViewModel

        @Namespace
        private var namespace

        @State
        private var imageSources: [ImageSource] = []

        let type: MediaViewModel.MediaType
        let action: (Namespace.ID) -> Void

        private var useTitleLabel: Bool {
            if useRandomImage || type == .downloads || type == .favorites {
                return true
            }

            #if os(tvOS)
            return type == .trending || type == .upcoming
            #else
            return false
            #endif
        }

        private func setImageSources() {
            Task { @MainActor in
                #if os(tvOS)
                let isSeerrLibrary = type == .trending || type == .upcoming
                #else
                let isSeerrLibrary = false
                #endif

                if useRandomImage || isSeerrLibrary {
                    self.imageSources = try await viewModel.randomItemImageSources(for: type)
                    return
                }

                if case let MediaViewModel.MediaType.collectionFolder(item) = type {
                    self.imageSources = [item.imageSource(.primary, maxWidth: 500)]
                } else if case let MediaViewModel.MediaType.liveTV(item) = type {
                    self.imageSources = [item.imageSource(.primary, maxWidth: 500)]
                }
            }
        }

        @ViewBuilder
        private var titleLabel: some View {
            Text(type.displayTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(alignment: .center)
        }

        private func titleLabelOverlay(with content: some View) -> some View {
            ZStack {
                content

                Color.black
                    .opacity(0.5)

                titleLabel
                    .foregroundStyle(.white)
            }
        }

        private var mediaItemShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
        }

        private var primaryButtonContent: some View {
            Button {
                action(namespace)
            } label: {
                ImageView(imageSources)
                    .image { image in
                        if useTitleLabel {
                            titleLabelOverlay(with: image)
                        } else {
                            image
                        }
                    }
                    .placeholder { imageSource in
                        titleLabelOverlay(with: DefaultPlaceholderView(blurHash: imageSource.blurHash))
                    }
                    .failure {
                        Color.secondarySystemFill
                            .opacity(0.75)
                            .overlay {
                                titleLabel
                                    .foregroundColor(.primary)
                            }
                    }
                    .id(imageSources.hashValue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .posterAspectRatio(.landscape)
                    .backport
                    .matchedTransitionSource(id: "item", in: namespace)
            }
        }

        @ViewBuilder
        private var primaryButton: some View {
            #if os(iOS)
            if #available(iOS 26.0, *) {
                primaryButtonContent
                    .buttonStyle(.plain)
            } else {
                primaryButtonContent
                    .buttonStyle(.card)
            }
            #else
            primaryButtonContent
                .buttonStyle(.card)
            #endif
        }

        @ViewBuilder
        private var mediaItemVisual: some View {
            #if os(iOS)
            let content = primaryButton
                .contentShape(.contextMenuPreview, Rectangle())
                .containerShape(mediaItemShape)

            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.clear, in: mediaItemShape)
                    .compositingGroup()
                    .clipShape(mediaItemShape)
            } else {
                content
                    .compositingGroup()
                    .clipShape(mediaItemShape)
                    .overlay {
                        mediaItemShape
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }
            }
            #else
            primaryButton
            #endif
        }

        @ViewBuilder
        private var styledMediaItemVisual: some View {
            #if os(iOS)
            mediaItemVisual
                .posterShadow()
            #else
            mediaItemVisual
            #endif
        }

        var body: some View {
            styledMediaItemVisual
                .onFirstAppear(perform: setImageSources)
                .backport
                .onChange(of: useRandomImage) { _, _ in
                    setImageSources()
                }
        }
    }
}
