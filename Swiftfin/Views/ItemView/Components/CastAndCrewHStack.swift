//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension PlatformItemView {

    struct CastAndCrewHStack: View {

        @Router
        private var router

        let people: [BaseItemPerson]

        var body: some View {
            PlatformPosterHStack(
                title: L10n.castAndCrew.localizedCapitalized,
                type: .square,
                items: people.filter { person in
                    person.type?.isSupported ?? false
                },
                headerAction: {
                    router.route(to: .castAndCrew(people: people, itemID: nil))
                }
            ) { person in
                CirclePersonButton(person: person) { namespace in
                    router.route(to: .item(item: .init(person: person)), in: namespace)
                }
            }
            .itemColumnCount(UIDevice.isPhone ? 3 : 6)
            .itemLabelHeight(80)
        }
    }
}
