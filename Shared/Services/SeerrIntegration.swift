//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import Foundation

enum SeerrIntegration {
    static var serverURLString: String {
        Defaults[.Integrations.Seerr.serverURL]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var serverURL: URL? {
        let value = serverURLString

        guard !value.isEmpty,
              let url = URL(string: value),
              url.scheme != nil,
              url.host != nil
        else {
            return nil
        }

        return url
    }

    static var apiKeyKeychainKey: String {
        guard let userID = Container.shared.currentUserSession()?.user.id else {
            return "seerr-api-key"
        }

        return "\(userID)-seerr-api-key"
    }

    static var apiKey: String? {
        let apiKey = Container.shared.keychainService()
            .get(apiKeyKeychainKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return apiKey?.isEmpty == false ? apiKey : nil
    }
}
