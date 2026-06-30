//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct UnifiedGenre: Hashable, Identifiable {

    let id: String
    let displayTitle: String
    let jellyfinNames: [String]
    let seerrMovieGenreIDs: [Int]
    let seerrTVGenreIDs: [Int]
    let artworkPath: String?

    init(
        id: String,
        displayTitle: String,
        jellyfinNames: [String],
        seerrMovieGenreIDs: [Int] = [],
        seerrTVGenreIDs: [Int] = [],
        artworkPath: String? = nil
    ) {
        self.id = id
        self.displayTitle = displayTitle
        self.jellyfinNames = jellyfinNames
        self.seerrMovieGenreIDs = seerrMovieGenreIDs
        self.seerrTVGenreIDs = seerrTVGenreIDs
        self.artworkPath = artworkPath
    }

    var jellyfinGenres: [ItemGenre] {
        jellyfinNames.map(ItemGenre.init)
    }

    var artworkImageSources: [ImageSource] {
        [ImageSource(url: SeerrClient.tmdbImageURL(path: artworkPath))].filter { $0.url != nil }
    }
}

enum UnifiedGenreTaxonomy {

    static let allGenres: [UnifiedGenre] = [
        .init(
            id: "action",
            displayTitle: "Action",
            jellyfinNames: ["Action", "Action & Adventure", "Action and Adventure"],
            seerrMovieGenreIDs: [28],
            seerrTVGenreIDs: [10759],
            artworkPath: "/7EcMZJ4UQvMW7Awxc1DvcH3jnT.jpg"
        ),
        .init(
            id: "adventure",
            displayTitle: "Adventure",
            jellyfinNames: ["Adventure", "Action & Adventure", "Action and Adventure"],
            seerrMovieGenreIDs: [12],
            seerrTVGenreIDs: [10759],
            artworkPath: "/xvKgVY5Ho26qWzCnPrUPnfC4agE.jpg"
        ),
        .init(
            id: "animation",
            displayTitle: "Animation",
            jellyfinNames: ["Animation", "Animated"],
            seerrMovieGenreIDs: [16],
            seerrTVGenreIDs: [16],
            artworkPath: "/xEIGPk5QTxD9E5knNFSXggNxEAP.jpg"
        ),
        .init(
            id: "comedy",
            displayTitle: "Comedy",
            jellyfinNames: ["Comedy"],
            seerrMovieGenreIDs: [35],
            seerrTVGenreIDs: [35],
            artworkPath: "/Ap6u3M5W0Lg2yiMrmdOZpnIW1Zk.jpg"
        ),
        .init(
            id: "crime",
            displayTitle: "Crime",
            jellyfinNames: ["Crime"],
            seerrMovieGenreIDs: [80],
            seerrTVGenreIDs: [80],
            artworkPath: "/8VKv0silVVUvpYblHqNNyRBs3Wu.jpg"
        ),
        .init(
            id: "documentary",
            displayTitle: "Documentary",
            jellyfinNames: ["Documentary", "Documentaries"],
            seerrMovieGenreIDs: [99],
            seerrTVGenreIDs: [99],
            artworkPath: "/dqvgbg4YSpk4ejoYZZaNorQTH7X.jpg"
        ),
        .init(
            id: "drama",
            displayTitle: "Drama",
            jellyfinNames: ["Drama"],
            seerrMovieGenreIDs: [18],
            seerrTVGenreIDs: [18],
            artworkPath: "/8eihUxjQsJ7WvGySkVMC0EwbPAD.jpg"
        ),
        .init(
            id: "fantasy",
            displayTitle: "Fantasy",
            jellyfinNames: ["Fantasy", "Sci-Fi & Fantasy", "Sci Fi & Fantasy", "Sci-Fi and Fantasy"],
            seerrMovieGenreIDs: [14],
            seerrTVGenreIDs: [10765],
            artworkPath: "/pm0RiwNpSja8gR0BTWpxo5a9Bbl.jpg"
        ),
        .init(
            id: "history",
            displayTitle: "History",
            jellyfinNames: ["History", "Historical"],
            seerrMovieGenreIDs: [36],
            artworkPath: "/lnxTTpHzpjgla7YX8MGkQG2bg0Y.jpg"
        ),
        .init(
            id: "horror",
            displayTitle: "Horror",
            jellyfinNames: ["Horror"],
            seerrMovieGenreIDs: [27],
            artworkPath: "/8Z8njxARIoyt57agKeiCxnKWIiW.jpg"
        ),
        .init(
            id: "kids-family",
            displayTitle: "Kids & Family",
            jellyfinNames: ["Kids", "Children", "Children's", "Family"],
            seerrMovieGenreIDs: [10751],
            seerrTVGenreIDs: [10751, 10762],
            artworkPath: "/9DEpAWQt8ISOxEJQjlvHMRDsebK.jpg"
        ),
        .init(
            id: "music",
            displayTitle: "Music",
            jellyfinNames: ["Music", "Musical"],
            seerrMovieGenreIDs: [10402],
            artworkPath: "/g3RQjjBoWaJXqsIcsjGEslwHVh3.jpg"
        ),
        .init(
            id: "mystery",
            displayTitle: "Mystery",
            jellyfinNames: ["Mystery"],
            seerrMovieGenreIDs: [9648],
            seerrTVGenreIDs: [9648],
            artworkPath: "/9x9utXc396rt9zKW3sjvLhAM4Ja.jpg"
        ),
        .init(
            id: "news",
            displayTitle: "News",
            jellyfinNames: ["News"],
            seerrTVGenreIDs: [10763],
            artworkPath: "/i3eFaFQEc5SiWuJMRZhN7xnB4H6.jpg"
        ),
        .init(
            id: "politics",
            displayTitle: "Politics",
            jellyfinNames: ["Politics", "War & Politics", "War and Politics"],
            seerrTVGenreIDs: [10768],
            artworkPath: "/beiYFV811grDtFqNBYLCUfSa6RG.jpg"
        ),
        .init(
            id: "reality",
            displayTitle: "Reality",
            jellyfinNames: ["Reality"],
            seerrTVGenreIDs: [10764],
            artworkPath: "/4B2gLhckNDfv0qQQ38KuTxzX2Xb.jpg"
        ),
        .init(
            id: "romance",
            displayTitle: "Romance",
            jellyfinNames: ["Romance"],
            seerrMovieGenreIDs: [10749],
            artworkPath: "/xd5SYDUhNVGLUeK2epbEjnVBpPN.jpg"
        ),
        .init(
            id: "science-fiction",
            displayTitle: "Sci-Fi",
            jellyfinNames: ["Science Fiction", "Sci Fi", "Sci-Fi", "SciFi", "Sci-Fi & Fantasy", "Sci Fi & Fantasy", "Sci-Fi and Fantasy"],
            seerrMovieGenreIDs: [878],
            seerrTVGenreIDs: [10765],
            artworkPath: "/AdYJMNhcXVeqjRenSHP88oaLCaC.jpg"
        ),
        .init(
            id: "soap",
            displayTitle: "Soap",
            jellyfinNames: ["Soap"],
            seerrTVGenreIDs: [10766],
            artworkPath: "/sCTNR6iYgEAaYxjvibhzt8sc1nQ.jpg"
        ),
        .init(
            id: "talk",
            displayTitle: "Talk",
            jellyfinNames: ["Talk"],
            seerrTVGenreIDs: [10767],
            artworkPath: "/ruDMkCAH8dz69bDuWT5Xs19GK3N.jpg"
        ),
        .init(
            id: "thriller",
            displayTitle: "Thriller",
            jellyfinNames: ["Thriller"],
            seerrMovieGenreIDs: [53],
            artworkPath: "/5lTZyuBTNOfawsfPT8Q0cIg6qAF.jpg"
        ),
        .init(
            id: "war",
            displayTitle: "War",
            jellyfinNames: ["War", "War & Politics", "War and Politics"],
            seerrMovieGenreIDs: [10752],
            seerrTVGenreIDs: [10768],
            artworkPath: "/ddIkmH3TpR6XSc47jj0BrGK5Rbz.jpg"
        ),
        .init(
            id: "western",
            displayTitle: "Western",
            jellyfinNames: ["Western"],
            seerrMovieGenreIDs: [37],
            seerrTVGenreIDs: [37],
            artworkPath: "/x4biAVdPVCghBlsVIzB6NmbghIz.jpg"
        ),
    ]

    static func genres(for jellyfinGenre: ItemGenre) -> [UnifiedGenre] {
        genres(forJellyfinName: jellyfinGenre.value)
    }

    static func genres(forJellyfinName name: String) -> [UnifiedGenre] {
        let normalizedName = normalized(name)

        return allGenres.filter { genre in
            genre.jellyfinNames.contains { normalized($0) == normalizedName }
        }
    }

    static func genre(withID id: String) -> UnifiedGenre? {
        allGenres.first { $0.id == id }
    }

    static func normalized(_ value: String) -> String {
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
