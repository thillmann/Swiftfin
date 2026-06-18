//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

extension HomeView {

    struct NextUpView: View {

        @Default(.Customization.nextUpPosterType)
        private var nextUpPosterType

        @Router
        private var router

        @ObservedObject
        var viewModel: NextUpLibraryViewModel

        let onFirstPosterFocused: () -> Void

        init(
            viewModel: NextUpLibraryViewModel,
            onFirstPosterFocused: @escaping () -> Void = {}
        ) {
            self.viewModel = viewModel
            self.onFirstPosterFocused = onFirstPosterFocused
        }

        var body: some View {
            if viewModel.elements.isNotEmpty {
                PosterHStack(
                    title: L10n.nextUp,
                    type: nextUpPosterType,
                    items: viewModel.elements
                ) { item in
                    FocusReportingPosterButton(
                        item: item,
                        type: nextUpPosterType,
                        isFirstItem: item.id != nil && item.id == viewModel.elements.first?.id,
                        onFirstPosterFocused: onFirstPosterFocused
                    ) {
                        router.route(to: .item(item: item))
                    }
                }
            }
        }
    }

    private struct FocusReportingPosterButton: View {

        let item: BaseItemDto
        let type: PosterDisplayType
        let isFirstItem: Bool
        let onFirstPosterFocused: () -> Void
        let action: () -> Void

        @FocusState
        private var isFocused: Bool

        var body: some View {
            PosterButton(
                item: item,
                type: type,
                action: action
            )
            .focused($isFocused)
            .onChange(of: isFocused) { _, newValue in
                if newValue, isFirstItem {
                    onFirstPosterFocused()
                }
            }
        }
    }
}
