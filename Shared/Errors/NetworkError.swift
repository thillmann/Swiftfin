//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum NetworkFailure: Hashable {

    case cannotConnect
    case cannotFindHost
    case timedOut

    var message: String {
        switch self {
        case .cannotConnect:
            L10n.cannotConnectToHost
        case .cannotFindHost:
            L10n.unableToFindHost
        case .timedOut:
            L10n.networkTimedOut
        }
    }
}

extension Error {

    var networkFailure: NetworkFailure? {
        let error = self as NSError

        if error.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: error.code) {
            case .cannotFindHost, .dnsLookupFailed:
                return .cannotFindHost
            case .timedOut:
                return .timedOut
            case .cannotConnectToHost,
                 .dataNotAllowed,
                 .internationalRoamingOff,
                 .networkConnectionLost,
                 .notConnectedToInternet:
                return .cannotConnect
            default:
                break
            }
        }

        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? Error,
           let failure = underlyingError.networkFailure
        {
            return failure
        }

        return nil
    }
}
