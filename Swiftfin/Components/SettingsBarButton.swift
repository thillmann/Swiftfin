//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

struct SettingsBarButton: View {

    enum Appearance {
        case profile
        case toolbarIcon
    }

    let server: ServerState
    let user: UserState
    private let appearance: Appearance
    let action: () -> Void

    init(
        server: ServerState,
        user: UserState,
        appearance: Appearance = .profile,
        action: @escaping () -> Void
    ) {
        self.server = server
        self.user = user
        self.appearance = appearance
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            buttonContent
        }
        .frame(width: buttonSize, height: buttonSize)
        .clipShape(.circle)
        .buttonBorderShape(.circle)
        .accessibilityLabel(L10n.settings)
    }

    @ViewBuilder
    private var buttonContent: some View {
        switch appearance {
        case .profile:
            ImageView(
                user.profileImageSource(
                    client: server.client
                )
            )
            .pipeline(.Swiftfin.local)
            .image { image in
                image.aspectRatio(contentMode: .fill)
            }
            .placeholder { _ in
                profileFallback
            }
            .failure {
                profileFallback
            }
            .id(user.id)
        case .toolbarIcon:
            Image(systemName: "person.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var buttonSize: CGFloat {
        switch appearance {
        case .profile:
            44
        case .toolbarIcon:
            24
        }
    }

    private var profileFallback: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.gray, in: Circle())
    }
}
