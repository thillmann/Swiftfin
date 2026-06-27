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
import JellyfinAPI

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

    static var isConfigured: Bool {
        serverURL != nil && apiKey != nil
    }

    static var isAvailable: Bool {
        Defaults[.Integrations.Seerr.isEnabled] && isConfigured
    }

    static func upcomingEpisodePillLabel(for item: BaseItemDto, userSession: UserSession) async -> String? {
        guard isAvailable else {
            return nil
        }

        guard let tmdbID = await tmdbProviderID(for: item, userSession: userSession) else {
            return nil
        }

        let result = await SeerrClient.tvDetails(id: tmdbID)

        switch result {
        case let .success(details):
            guard let nextEpisode = details.nextEpisodeToAir else {
                return nil
            }

            guard let label = nextEpisode.upcomingEpisodePillLabel else {
                return nil
            }

            return label
        case .failure:
            return nil
        }
    }

    private static func tmdbProviderID(for item: BaseItemDto, userSession: UserSession) async -> Int? {
        if let providerID = item.tmdbProviderID {
            return providerID
        }

        do {
            return try await item.getFullItem(userSession: userSession).tmdbProviderID
        } catch {
            return nil
        }
    }
}

private extension BaseItemDto {

    var tmdbProviderID: Int? {
        guard let providerID = providerIDs?.first(where: { providerID in
            providerID.key.compare("Tmdb", options: .caseInsensitive) == .orderedSame
        }) else {
            return nil
        }

        return Int(providerID.value)
    }
}

private extension SeerrClient.TVDetails.Episode {

    var upcomingEpisodePillLabel: String? {
        guard let airDate else { return nil }

        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"

        guard let date = parser.date(from: airDate) else {
            return L10n.newEpisodeOn(airDate)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"

        return L10n.newEpisodeOn(formatter.string(from: date))
    }
}
