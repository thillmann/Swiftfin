//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct SeerrGenreMapping: Hashable {
    let movieGenreID: Int?
    let tvGenreID: Int?
}

enum SeerrGenreMapper {

    static func mapping(for genre: ItemGenre) -> SeerrGenreMapping? {
        mapping(for: genre.value)
    }

    static func mapping(for genreName: String) -> SeerrGenreMapping? {
        mappings[normalized(genreName)]
    }

    private static let mappings: [String: SeerrGenreMapping] = {
        var mappings: [String: SeerrGenreMapping] = [:]

        func add(_ names: [String], movieGenreID: Int? = nil, tvGenreID: Int? = nil) {
            let mapping = SeerrGenreMapping(movieGenreID: movieGenreID, tvGenreID: tvGenreID)
            for name in names {
                mappings[normalized(name)] = mapping
            }
        }

        add(["Action"], movieGenreID: 28, tvGenreID: 10759)
        add(["Action & Adventure", "Action and Adventure"], movieGenreID: nil, tvGenreID: 10759)
        add(["Adventure"], movieGenreID: 12, tvGenreID: 10759)
        add(["Animation", "Animated"], movieGenreID: 16, tvGenreID: 16)
        add(["Comedy"], movieGenreID: 35, tvGenreID: 35)
        add(["Crime"], movieGenreID: 80, tvGenreID: 80)
        add(["Documentary", "Documentaries"], movieGenreID: 99, tvGenreID: 99)
        add(["Drama"], movieGenreID: 18, tvGenreID: 18)
        add(["Family"], movieGenreID: 10751, tvGenreID: 10751)
        add(["Fantasy"], movieGenreID: 14, tvGenreID: 10765)
        add(["History", "Historical"], movieGenreID: 36, tvGenreID: nil)
        add(["Horror"], movieGenreID: 27, tvGenreID: nil)
        add(["Kids", "Children", "Children's"], movieGenreID: nil, tvGenreID: 10762)
        add(["Music", "Musical"], movieGenreID: 10402, tvGenreID: nil)
        add(["Mystery"], movieGenreID: 9648, tvGenreID: 9648)
        add(["News"], movieGenreID: nil, tvGenreID: 10763)
        add(["Reality"], movieGenreID: nil, tvGenreID: 10764)
        add(["Romance"], movieGenreID: 10749, tvGenreID: nil)
        add(["Science Fiction", "Sci Fi", "Sci-Fi", "SciFi"], movieGenreID: 878, tvGenreID: 10765)
        add(["Sci-Fi & Fantasy", "Sci Fi & Fantasy", "Sci-Fi and Fantasy"], movieGenreID: nil, tvGenreID: 10765)
        add(["Soap"], movieGenreID: nil, tvGenreID: 10766)
        add(["Talk"], movieGenreID: nil, tvGenreID: 10767)
        add(["Thriller"], movieGenreID: 53, tvGenreID: nil)
        add(["TV Movie", "Television Movie"], movieGenreID: 10770, tvGenreID: nil)
        add(["War"], movieGenreID: 10752, tvGenreID: 10768)
        add(["War & Politics", "War and Politics", "Politics"], movieGenreID: nil, tvGenreID: 10768)
        add(["Western"], movieGenreID: 37, tvGenreID: 37)

        return mappings
    }()

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
