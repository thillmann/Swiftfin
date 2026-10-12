//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI
import SwiftUI

// TODO: remove and flatten to `PlatformPagingLibraryView`

// TODO: sorting by number/filtering
//       - see if can use normal filter view model?
//       - how to add custom filters for data context?
// TODO: saving item display type/detailed column count
//       - wait until after user refactor

// Note: Repurposes `LibraryDisplayType` to save from creating a new type.
//       If there are other places where detailed/compact contextually differ
//       from the library types, then create a new type and use it here.
//       - list: detailed
//       - grid: compact

struct ChannelLibraryView: View {

    @Router
    private var router

    @State
    private var channelDisplayType: LibraryDisplayType = .list

    @StateObject
    private var viewModel = ChannelLibraryViewModel()

    // MARK: item view

    private func compactChannelView(channel: ChannelProgram) -> some View {
        CompactChannelView(channel: channel.channel) {
            guard let userSession = viewModel.userSession else { return }
            guard let provider = channel.channel.getPlaybackItemProvider(userSession: userSession) else { return }

            router.route(
                to: .videoPlayer(
                    provider: provider
                )
            )
        }
    }

    private func detailedChannelView(channel: ChannelProgram) -> some View {
        DetailedChannelView(channel: channel) {
            guard let userSession = viewModel.userSession else { return }
            guard let provider = channel.channel.getPlaybackItemProvider(userSession: userSession) else { return }

            router.route(
                to: .videoPlayer(
                    provider: provider
                )
            )
        }
    }

    private var gridSpacing: CGFloat {
        channelDisplayType == .grid ? EdgeInsets.edgePadding / 2 : 0
    }

    private var horizontalPadding: CGFloat {
        channelDisplayType == .grid ? EdgeInsets.edgePadding : 0
    }

    private var columns: [GridItem] {
        switch (channelDisplayType, UIDevice.isPhone) {
        case (.grid, true):
            Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 3)
        case (.grid, false):
            [GridItem(.adaptive(minimum: 150), spacing: gridSpacing)]
        case (.list, true):
            [GridItem(.flexible(), spacing: 0)]
        case (.list, false):
            [GridItem(.adaptive(minimum: 250), spacing: 0)]
        }
    }

    @ViewBuilder
    private var contentView: some View {
        PosterVGrid(
            data: viewModel.items,
            columns: columns,
            spacing: gridSpacing,
            horizontalPadding: horizontalPadding,
            onNeedsNextPage: { viewModel.loadNextPageIfNeeded(currentItem: $0) },
            renderID: AnyHashable(channelDisplayType.rawValue),
            header: { EmptyView() }
        ) { channel in
            switch channelDisplayType {
            case .grid:
                compactChannelView(channel: channel)
            case .list:
                detailedChannelView(channel: channel)
            }
        }
    }

    var body: some View {
        ZStack {
            Color.clear

            switch viewModel.state {
            case .content:
                if viewModel.items.isEmpty {
                    ContentUnavailableView(L10n.noChannels.localizedCapitalized, systemImage: "antenna.radiowaves.left.and.right")
                } else {
                    contentView
                }

            case let .error(error):
                ErrorView(error: error)

            case .initial, .refreshing:
                ProgressView()
            }
        }
        .navigationTitle(L10n.channels)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            viewModel.send(.refresh)
        }
        .onFirstAppear {
            if viewModel.state == .initial {
                viewModel.send(.refresh)
            }
        }
        .sinceLastDisappear { interval in
            // refresh after 3 hours
            if interval >= 10800 {
                viewModel.send(.refresh)
            }
        }
        .topBarTrailing {

            if viewModel.backgroundStates.contains(.gettingNextPage) {
                ProgressView()
            }

            Menu {
                // We repurposed `LibraryDisplayType` but want different labels
                Picker(L10n.channelDisplay, selection: $channelDisplayType) {

                    Label(L10n.compact, systemImage: LibraryDisplayType.grid.systemImage)
                        .tag(LibraryDisplayType.grid)

                    Label(L10n.detailed, systemImage: LibraryDisplayType.list.systemImage)
                        .tag(LibraryDisplayType.list)
                }
            } label: {
                Label(
                    channelDisplayType.displayTitle,
                    systemImage: channelDisplayType.systemImage
                )
            }
        }
    }
}
