//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

@MainActor
final class TopShelfDeepLinkStore: ObservableObject {

    struct Destination {
        enum Action: String {
            case display
            case play
        }

        let userID: String
        let itemID: String
        let action: Action
    }

    static let shared = TopShelfDeepLinkStore()

    @Published
    private(set) var pendingURL: URL?

    private init() {}

    func receive(_ url: URL) {
        guard destination(for: url) != nil else { return }
        pendingURL = url
    }

    func consume(_ url: URL) {
        guard pendingURL == url else { return }
        pendingURL = nil
    }

    func destination(for url: URL) -> Destination? {
        guard url.scheme?.lowercased() == "jellyfin",
              url.host?.lowercased() == "users"
        else {
            return nil
        }

        let path = url.pathComponents.filter { $0 != "/" }

        guard path.count == 3,
              path[1].lowercased() == "items",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let actionValue = components.queryItems?.first(where: { $0.name == "action" })?.value,
              let action = Destination.Action(rawValue: actionValue)
        else {
            return nil
        }

        return Destination(
            userID: path[0],
            itemID: path[2],
            action: action
        )
    }
}
