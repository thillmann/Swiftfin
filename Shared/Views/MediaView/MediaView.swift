//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionVGrid
import Defaults
import Engine
import JellyfinAPI
import SwiftUI

struct MediaView: View {

    @Router
    private var router

    @StateObject
    private var viewModel = MediaViewModel()

    #if os(tvOS)
    private var layout: CollectionVGridLayout {
        if UIDevice.isTV {
            .columns(4, insets: .init(50), itemSpacing: 50, lineSpacing: 50)
        } else {
            .columns(2)
        }
    }
    #else
    private var columns: [GridItem] {
        if UIDevice.isPad {
            [GridItem(.adaptive(minimum: 200), spacing: 10)]
        } else {
            Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
        }
    }
    #endif

    private func select(_ mediaType: MediaViewModel.MediaType, in namespace: Namespace.ID) {
        switch mediaType {
        case let .collectionFolder(item):
            let viewModel = ItemLibraryViewModel(
                parent: item,
                filters: .default
            )
            router.route(to: .library(viewModel: viewModel), in: namespace)

        case .downloads:
            router.route(to: .downloadList)

        case .favorites:
            // TODO: favorites should have its own view instead of a library
            let viewModel = ItemLibraryViewModel(
                title: L10n.favorites,
                id: "favorites",
                filters: .favorites
            )
            router.route(to: .library(viewModel: viewModel), in: namespace)

        case .liveTV:
            router.route(to: .liveTV)

        #if os(tvOS)
        case .trending:
            router.route(to: .seerrTrending, in: namespace)

        case .upcoming:
            router.route(to: .seerrUpcoming(), in: namespace)
        #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text(L10n.allMedia.localizedCapitalized)
                    .font(.largeTitle.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.top, UIDevice.isPad ? 80 : 60)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(viewModel.mediaItems, id: \.self) { mediaType in
                        MediaItem(viewModel: viewModel, type: mediaType) { namespace in
                            select(mediaType, in: namespace)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
        #else
        CollectionVGrid(
            uniqueElements: viewModel.mediaItems,
            layout: layout
        ) { mediaType in
            MediaItem(viewModel: viewModel, type: mediaType) { namespace in
                select(mediaType, in: namespace)
            }
        }
        #endif
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch viewModel.state {
        case .initial:
            EmptyView()

        case .refreshing:
            ProgressView()
                .padding(12)
                .background(.regularMaterial, in: Capsule())
                .allowsHitTesting(false)

        case .error:
            if let error = viewModel.error {
                HStack(spacing: 12) {
                    Image(systemName: error.networkFailure == nil ? "exclamationmark.circle" : "wifi.slash")
                        .foregroundStyle(.red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.networkFailure == nil ? error.localizedDescription : L10n.connectionFailed)
                            .font(.footnote.weight(.semibold))

                        if let networkFailure = error.networkFailure {
                            Text(networkFailure.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(2)

                    Spacer(minLength: 8)

                    Button(L10n.retry) {
                        viewModel.refresh()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    var body: some View {
        ZStack {
            Color.clear

            if viewModel.mediaItems.isNotEmpty {
                content
            } else {
                switch viewModel.state {
                case .initial, .refreshing:
                    ProgressView()
                case .error:
                    viewModel.error.map {
                        ErrorView(error: $0)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.mediaItems.isNotEmpty {
                statusOverlay
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.linear(duration: 0.1), value: viewModel.state)
        .refreshable {
            viewModel.refresh()
        }
        .onFirstAppear {
            viewModel.refresh()
        }
        #if os(iOS)
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        #else
        .ignoresSafeArea()
        .navigationTitle(L10n.allMedia.localizedCapitalized)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}
