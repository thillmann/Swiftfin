//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

extension BaseItemDto {
    @MainActor
    func getFullItem(userSession: UserSession) async throws -> BaseItemDto {
        let entry = try await userSession.getFullItem(self)
        guard let value = entry.value else { throw ItemStore.StoreError.itemUnavailable }

        return value
    }
}
