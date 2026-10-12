//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

extension PlatformItemView {

    struct FeatureUserDataButton: View {

        enum Action {
            case favorite
            case played
        }

        @ObservedObject
        var viewModel: ItemViewModel
        let action: Action

        private var isSelected: Bool {
            switch action {
            case .favorite:
                viewModel.item.userData?.isFavorite == true
            case .played:
                viewModel.item.userData?.isPlayed == true
            }
        }

        private var imageName: String {
            switch action {
            case .favorite:
                isSelected ? "heart.fill" : "heart"
            case .played:
                isSelected ? "checkmark" : "plus"
            }
        }

        private var accessibilityLabel: String {
            switch action {
            case .favorite:
                isSelected ? L10n.favorited : L10n.favorite
            case .played:
                isSelected ? L10n.unplayed : L10n.played
            }
        }

        var body: some View {
            Button {
                switch action {
                case .favorite:
                    viewModel.send(.toggleIsFavorite)
                case .played:
                    viewModel.send(.toggleIsPlayed)
                }
            } label: {
                Image(systemName: imageName)
                    .id(isSelected)
                    .font(FeatureButtonTokens.labelFont)
                    .transition(.scale.combined(with: .opacity))
            }
            .buttonStyle(.featureIconButton)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    struct ActionButtonHStack: View {

        @Default(.accentColor)
        private var accentColor

        @StoredValue(.User.enabledTrailers)
        private var enabledTrailers: TrailerSelection

        @ObservedObject
        var viewModel: ItemViewModel

        var equalSpacing: Bool = true

        // MARK: - Has Trailers

        private var hasTrailers: Bool {
            guard !viewModel.isOffline else { return false }

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
            HStack(alignment: .center, spacing: 10) {

                if viewModel.item.canBePlayed, !viewModel.isOffline {

                    // MARK: - Toggle Played

                    let isCheckmarkSelected = viewModel.item.userData?.isPlayed == true

                    Button(L10n.played, systemImage: "checkmark") {
                        viewModel.send(.toggleIsPlayed)
                    }
                    .buttonStyle(.tintedMaterial(tint: .jellyfinPurple, foregroundColor: .white))
                    .isSelected(isCheckmarkSelected)
                    .animation(
                        .spring(response: 0.3, dampingFraction: 0.7),
                        value: isCheckmarkSelected
                    )
                    .frame(maxWidth: .infinity)
                    .if(!equalSpacing) { view in
                        view.aspectRatio(1, contentMode: .fit)
                    }
                }

                // MARK: - Toggle Favorite

                if !viewModel.isOffline {
                    let isHeartSelected = viewModel.item.userData?.isFavorite == true

                    Button(L10n.favorite, systemImage: isHeartSelected ? "heart.fill" : "heart") {
                        viewModel.send(.toggleIsFavorite)
                    }
                    .buttonStyle(.tintedMaterial(tint: .red, foregroundColor: .white))
                    .isSelected(isHeartSelected)
                    .animation(
                        .spring(response: 0.3, dampingFraction: 0.7),
                        value: isHeartSelected
                    )
                    .frame(maxWidth: .infinity)
                    .if(!equalSpacing) { view in
                        view.aspectRatio(1, contentMode: .fit)
                    }
                }

                // MARK: - Watch a Trailer

                if hasTrailers {
                    TrailerMenu(
                        localTrailers: viewModel.localTrailers,
                        externalTrailers: viewModel.item.remoteTrailers ?? []
                    )
                    .menuStyle(.button)
                    .frame(maxWidth: .infinity)
                    .if(!equalSpacing) { view in
                        view.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .font(.title3)
            .fontWeight(.semibold)
            .buttonStyle(.material)
            .labelStyle(.iconOnly)
        }
    }
}
