//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ItemView {

    struct ActionButtonHStack: View {

        @StoredValue(.User.enabledTrailers)
        private var enabledTrailers: TrailerSelection

        // MARK: - Observed, State, & Environment Objects

        @Router
        private var router

        @ObservedObject
        var viewModel: ItemViewModel

        private var iconFont: Font {
            .system(size: FeatureButtonTokens.baseHeight * 0.4, weight: .semibold)
        }

        // MARK: - Has Trailers

        private var hasTrailers: Bool {
            if enabledTrailers.contains(.local), viewModel.localTrailers.isNotEmpty {
                return true
            }

            if enabledTrailers.contains(.external), viewModel.item.remoteTrailers?.isNotEmpty == true {
                return true
            }

            return false
        }

        // MARK: - Body

        var body: some View {
            HStack(alignment: .center, spacing: 20) {

                // MARK: Toggle Played

                if viewModel.item.canBePlayed {
                    let isCheckmarkSelected = viewModel.item.userData?.isPlayed == true

                    Button {
                        viewModel.send(.toggleIsPlayed)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(iconFont)
                    }
                    .buttonStyle(.featureIconButton)
                    .isSelected(isCheckmarkSelected)
                    .accessibilityLabel(L10n.played)
                }

                // MARK: Toggle Favorite

                let isHeartSelected = viewModel.item.userData?.isFavorite == true

                Button {
                    viewModel.send(.toggleIsFavorite)
                } label: {
                    Image(systemName: isHeartSelected ? "heart.fill" : "heart")
                        .font(iconFont)
                }
                .buttonStyle(.featureIconButton)
                .isSelected(isHeartSelected)
                .accessibilityLabel(L10n.favorited)

                // MARK: Watch a Trailer

                if hasTrailers {
                    TrailerMenu(
                        localTrailers: viewModel.localTrailers,
                        externalTrailers: viewModel.item.remoteTrailers ?? []
                    )
                    .buttonStyle(.featureIconButton)
                }

                // MARK: Advanced Options

                if viewModel.item.showEditorMenu {
                    Menu {
                        ItemEditorMenu(item: viewModel.item)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(iconFont)
                            .rotationEffect(.degrees(90))
                    }
                    .buttonStyle(.featureIconButton)
                    .accessibilityLabel(L10n.advanced)
                }
            }
            .frame(height: 100)
            .labelStyle(.iconOnly)
        }
    }
}
