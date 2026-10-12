//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension PlatformItemView {

    struct SimpleItemContentView: View {

        private let castAndCrewSectionSpacing: CGFloat = 20
        private let sectionSpacing: CGFloat = 40

        @ObservedObject
        var viewModel: ItemViewModel

        var body: some View {
            VStack(spacing: sectionSpacing) {
                if let castAndCrew = viewModel.item.people, castAndCrew.isNotEmpty {
                    VStack(spacing: castAndCrewSectionSpacing) {
                        PlatformItemView.CastAndCrewHStack(people: castAndCrew)

                        PlatformItemView.AboutView(viewModel: viewModel)
                    }
                } else {
                    PlatformItemView.AboutView(viewModel: viewModel)
                }
            }
        }
    }
}
