//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum SeerrClient {
    enum MediaStatus: Int, Decodable, Equatable {
        case unknown = 1
        case pending = 2
        case processing = 3
        case partiallyAvailable = 4
        case available = 5

        var displayText: String {
            switch self {
            case .unknown:
                L10n.unknown
            case .pending:
                L10n.seerrStatusPending
            case .processing:
                L10n.seerrStatusProcessing
            case .partiallyAvailable:
                L10n.seerrStatusPartiallyAvailable
            case .available:
                L10n.seerrStatusAvailable
            }
        }
    }

    enum RequestMediaType: String, Encodable {
        case movie
        case tv
    }

    enum TMDBImageSize: String {
        case w92
        case w154
        case w185
        case w300
        case w342
        case w500
        case w780
        case w1280
        case original
    }

    struct Page<T: Decodable & Equatable>: Decodable, Equatable {
        let page: Int?
        let totalPages: Int?
        let totalResults: Int?
        let results: [T]
    }

    struct MediaResult: Decodable, Equatable, Identifiable {
        enum MediaType: String, Decodable, Equatable {
            case movie
            case tv
            case person
        }

        let id: Int
        let mediaType: MediaType?
        let title: String?
        let name: String?
        let overview: String?
        let posterPath: String?
        let backdropPath: String?
        let releaseDate: String?
        let firstAirDate: String?
        let originalLanguage: String?
        let voteAverage: Double?
        let mediaInfo: MediaInfo?

        var posterImageSource: ImageSource {
            ImageSource(url: SeerrClient.tmdbImageURL(path: posterPath, size: .w500))
        }

        var backdropImageSource: ImageSource {
            ImageSource(url: SeerrClient.tmdbImageURL(path: backdropPath, size: .w1280))
        }

        func updatingStatus(_ status: MediaStatus) -> MediaResult {
            .init(
                id: id,
                mediaType: mediaType,
                title: title,
                name: name,
                overview: overview,
                posterPath: posterPath,
                backdropPath: backdropPath,
                releaseDate: releaseDate,
                firstAirDate: firstAirDate,
                originalLanguage: originalLanguage,
                voteAverage: voteAverage,
                mediaInfo: .init(status: status.rawValue)
            )
        }
    }

    struct MediaInfo: Decodable, Equatable {
        let status: Int?

        var mediaStatus: MediaStatus? {
            guard let status else { return nil }
            return MediaStatus(rawValue: status)
        }
    }

    struct Cast: Decodable, Equatable, Identifiable {
        let id: Int
        let name: String?
        let character: String?
        let profilePath: String?
    }

    struct Genre: Decodable, Equatable {
        let id: Int?
        let name: String?
    }

    struct Season: Decodable, Equatable, Identifiable {
        let id: Int
        let name: String?
        let overview: String?
        let posterPath: String?
        let seasonNumber: Int?
        let episodeCount: Int?
    }

    struct MovieDetails: Decodable, Equatable {
        struct Credits: Decodable, Equatable {
            let cast: [Cast]?
        }

        let id: Int
        let title: String?
        let overview: String?
        let posterPath: String?
        let backdropPath: String?
        let releaseDate: String?
        let runtime: Int?
        let voteAverage: Double?
        let genres: [Genre]?
        let mediaInfo: MediaInfo?
        let credits: Credits?
    }

    struct TVDetails: Decodable, Equatable {
        struct Credits: Decodable, Equatable {
            let cast: [Cast]?
        }

        struct Episode: Decodable, Equatable {
            let id: Int?
            let name: String?
            let overview: String?
            let airDate: String?
            let episodeNumber: Int?
            let seasonNumber: Int?
        }

        let id: Int
        let name: String?
        let overview: String?
        let posterPath: String?
        let backdropPath: String?
        let firstAirDate: String?
        let nextEpisodeToAir: Episode?
        let voteAverage: Double?
        let genres: [Genre]?
        let seasons: [Season]?
        let mediaInfo: MediaInfo?
        let credits: Credits?
    }

    struct ServiceProfile: Decodable, Equatable, Identifiable {
        let id: Int
        let name: String?

        init(id: Int, name: String?) {
            self.id = id
            self.name = name
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)

            func intValue(for keys: [String]) -> Int? {
                for key in keys {
                    guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
                    if let value = try? container.decode(Int.self, forKey: codingKey) {
                        return value
                    }
                    if let stringValue = try? container.decode(String.self, forKey: codingKey),
                       let value = Int(stringValue)
                    {
                        return value
                    }
                }
                return nil
            }

            func stringValue(for keys: [String]) -> String? {
                for key in keys {
                    guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
                    if let value = try? container.decode(String.self, forKey: codingKey), !value.isEmpty {
                        return value
                    }
                }
                return nil
            }

            guard let id = intValue(for: ["id", "profileId", "qualityProfileId", "languageProfileId"]) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing profile id"))
            }

            self.id = id
            self.name = stringValue(for: ["name", "profileName", "title", "label"])
        }
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    struct ServiceRootFolder: Decodable, Equatable, Identifiable {
        let id: String
        let path: String

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let value = try? container.decode(String.self) {
                self.path = value
                self.id = value
                return
            }

            struct RootFolderObject: Decodable {
                let id: Int?
                let path: String?
            }

            let object = try container.decode(RootFolderObject.self)
            let resolvedPath = object.path ?? ""
            self.path = resolvedPath
            self.id = object.id.map(String.init) ?? resolvedPath
        }
    }

    struct ServiceInstance: Decodable, Equatable, Identifiable {
        let id: Int
        let name: String?
        let isDefault: Bool?
        let is4k: Bool?
        let activeProfileId: Int?
        let activeProfileName: String?
        let activeDirectory: String?
        let profiles: [ServiceProfile]?
        let qualityProfiles: [ServiceProfile]?
        let rootFolders: [ServiceRootFolder]?
        let languageProfiles: [ServiceProfile]?
    }

    struct ServiceInstanceDetails: Decodable, Equatable, Identifiable {
        let id: Int
        let name: String?
        let isDefault: Bool?
        let is4k: Bool?
        let activeProfileId: Int?
        let activeProfileName: String?
        let activeDirectory: String?
        let profiles: [ServiceProfile]?
        let qualityProfiles: [ServiceProfile]?
        let rootFolders: [ServiceRootFolder]?
        let languageProfiles: [ServiceProfile]?
    }

    enum RequestedSeasons: Encodable, Equatable {
        case specific([Int])
        case all

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .specific(seasons):
                try container.encode(seasons)
            case .all:
                try container.encode("all")
            }
        }
    }

    struct RequestOptions: Encodable, Equatable {
        let seasons: RequestedSeasons?
        let is4K: Bool?
        let serverID: Int?
        let profileID: Int?
        let rootFolder: String?
        let languageProfileID: Int?
        let userID: Int?
    }

    struct Status: Decodable, Equatable {
        struct AppData: Decodable, Equatable {
            let version: String?
            let initialized: Bool?
        }

        let version: String?
        let appData: AppData?
    }

    struct ProbeError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    static func status() async -> Result<Status, ProbeError> {
        let result = await request(path: "status")

        switch result {
        case let .success((data, http)):
            switch http.statusCode {
            case 200 ... 299:
                break
            case 401, 403:
                return .failure(ProbeError(message: "Seerr rejected the API key."))
            default:
                return .failure(ProbeError(message: "Seerr status failed with HTTP \(http.statusCode)."))
            }

            do {
                let status = try JSONDecoder().decode(Status.self, from: data)
                return .success(status)
            } catch {
                return .failure(ProbeError(message: "Seerr responded, but Swiftfin could not read the status."))
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    static func search(
        query: String,
        page: Int = 1,
        language: String? = nil
    ) async -> Result<Page<MediaResult>, ProbeError> {
        await decode(
            path: "search",
            queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "language", value: language),
            ],
            failurePrefix: "Seerr search failed"
        )
    }

    static func discoverMovies(
        page: Int = 1,
        language: String? = nil
    ) async -> Result<Page<MediaResult>, ProbeError> {
        await decode(
            path: "discover/movies",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "language", value: language),
            ],
            failurePrefix: "Seerr discover movies failed"
        )
    }

    static func discoverTV(
        page: Int = 1,
        language: String? = nil
    ) async -> Result<Page<MediaResult>, ProbeError> {
        await decode(
            path: "discover/tv",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "language", value: language),
            ],
            failurePrefix: "Seerr discover TV failed"
        )
    }

    static func discoverTrending(
        page: Int = 1,
        language: String? = nil
    ) async -> Result<Page<MediaResult>, ProbeError> {
        await decode(
            path: "discover/trending",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "language", value: language),
            ],
            failurePrefix: "Seerr trending failed"
        )
    }

    static func discoverUpcomingMovies(
        page: Int = 1,
        language: String? = nil
    ) async -> Result<Page<MediaResult>, ProbeError> {
        await decode(
            path: "discover/movies/upcoming",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "language", value: language),
            ],
            failurePrefix: "Seerr upcoming movies failed"
        )
    }

    static func discoverUpcomingTV(
        page: Int = 1,
        language: String? = nil
    ) async -> Result<Page<MediaResult>, ProbeError> {
        await decode(
            path: "discover/tv/upcoming",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "language", value: language),
            ],
            failurePrefix: "Seerr upcoming TV failed"
        )
    }

    static func movieDetails(
        id: Int,
        language: String? = nil
    ) async -> Result<MovieDetails, ProbeError> {
        await decode(
            path: "movie/\(id)",
            queryItems: [
                URLQueryItem(name: "language", value: language),
            ],
            failurePrefix: "Seerr movie details failed"
        )
    }

    static func tvDetails(
        id: Int,
        language: String? = nil
    ) async -> Result<TVDetails, ProbeError> {
        await decode(
            path: "tv/\(id)",
            queryItems: [
                URLQueryItem(name: "language", value: language),
            ],
            failurePrefix: "Seerr TV details failed"
        )
    }

    static func radarrServices() async -> Result<[ServiceInstance], ProbeError> {
        await decode(
            path: "service/radarr",
            queryItems: [],
            failurePrefix: "Seerr Radarr services failed"
        )
    }

    static func sonarrServices() async -> Result<[ServiceInstance], ProbeError> {
        await decode(
            path: "service/sonarr",
            queryItems: [],
            failurePrefix: "Seerr Sonarr services failed"
        )
    }

    static func radarrServiceDetails(id: Int) async -> Result<ServiceInstanceDetails, ProbeError> {
        await decode(
            path: "service/radarr/\(id)",
            queryItems: [],
            failurePrefix: "Seerr Radarr service details failed"
        )
    }

    static func sonarrServiceDetails(id: Int) async -> Result<ServiceInstanceDetails, ProbeError> {
        await decode(
            path: "service/sonarr/\(id)",
            queryItems: [],
            failurePrefix: "Seerr Sonarr service details failed"
        )
    }

    static func availableRadarrProfiles(id: Int) async -> Result<[ServiceProfile], ProbeError> {
        await decodeProfiles(
            path: "settings/radarr/\(id)/profiles",
            failurePrefix: "Seerr available Radarr profiles failed"
        )
    }

    static func availableSonarrProfiles(id: Int) async -> Result<[ServiceProfile], ProbeError> {
        // Seerr does not always expose a dedicated Sonarr profiles settings endpoint.
        // Pull profile options from the service details payload instead.
        await decodeProfiles(
            path: "service/sonarr/\(id)",
            failurePrefix: "Seerr available Sonarr profiles failed"
        )
    }

    static func request(
        mediaType: RequestMediaType,
        mediaID: Int,
        seasons: [Int]? = nil,
        is4K: Bool? = nil
    ) async -> Result<Void, ProbeError> {
        await request(
            mediaType: mediaType,
            mediaID: mediaID,
            options: .init(
                seasons: seasons.map(RequestedSeasons.specific),
                is4K: is4K,
                serverID: nil,
                profileID: nil,
                rootFolder: nil,
                languageProfileID: nil,
                userID: nil
            )
        )
    }

    static func request(
        mediaType: RequestMediaType,
        mediaID: Int,
        options: RequestOptions
    ) async -> Result<Void, ProbeError> {
        struct RequestPayload: Encodable {
            let mediaType: String
            let mediaID: Int
            let seasons: RequestedSeasons?
            let is4K: Bool?
            let serverID: Int?
            let profileID: Int?
            let rootFolder: String?
            let languageProfileID: Int?
            let userID: Int?

            enum CodingKeys: String, CodingKey {
                case mediaType
                case mediaID = "mediaId"
                case seasons
                case is4K = "is4k"
                case serverID = "serverId"
                case profileID = "profileId"
                case rootFolder
                case languageProfileID = "languageProfileId"
                case userID = "userId"
            }
        }

        let payload = RequestPayload(
            mediaType: mediaType.rawValue,
            mediaID: mediaID,
            seasons: options.seasons,
            is4K: options.is4K,
            serverID: options.serverID,
            profileID: options.profileID,
            rootFolder: options.rootFolder,
            languageProfileID: options.languageProfileID,
            userID: options.userID
        )

        let payloadData: Data
        do {
            payloadData = try JSONEncoder().encode(payload)
        } catch {
            return .failure(ProbeError(message: "Swiftfin could not create a Seerr request payload."))
        }

        let result = await request(
            path: "request",
            method: "POST",
            body: payloadData
        )

        switch result {
        case let .success((_, http)):
            switch http.statusCode {
            case 200 ... 299:
                return .success(())
            case 401, 403:
                return .failure(ProbeError(message: "Seerr rejected the API key."))
            default:
                return .failure(ProbeError(message: "Seerr request failed with HTTP \(http.statusCode)."))
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    private static func decode<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        failurePrefix: String
    ) async -> Result<T, ProbeError> {
        let result = await request(
            path: path,
            queryItems: queryItems
        )

        switch result {
        case let .success((data, http)):
            guard (200 ... 299).contains(http.statusCode) else {
                if http.statusCode == 401 || http.statusCode == 403 {
                    return .failure(ProbeError(message: "Seerr rejected the API key."))
                }
                return .failure(ProbeError(message: "\(failurePrefix) with HTTP \(http.statusCode)."))
            }

            do {
                return try .success(JSONDecoder().decode(T.self, from: data))
            } catch {
                return .failure(ProbeError(message: "Seerr responded, but Swiftfin could not read the response."))
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    private static func decodeProfiles(
        path: String,
        failurePrefix: String
    ) async -> Result<[ServiceProfile], ProbeError> {
        let result = await request(path: path)

        switch result {
        case let .success((data, http)):
            guard (200 ... 299).contains(http.statusCode) else {
                if http.statusCode == 401 || http.statusCode == 403 {
                    return .failure(ProbeError(message: "Seerr rejected the API key."))
                }
                return .failure(ProbeError(message: "\(failurePrefix) with HTTP \(http.statusCode)."))
            }

            do {
                if let direct = try? JSONDecoder().decode([ServiceProfile].self, from: data) {
                    return .success(direct)
                }

                struct WrappedProfiles: Decodable {
                    let profiles: [ServiceProfile]?
                    let qualityProfiles: [ServiceProfile]?
                    let results: [ServiceProfile]?
                    let data: [ServiceProfile]?
                }

                let wrapped = try JSONDecoder().decode(WrappedProfiles.self, from: data)
                let resolved = wrapped.profiles ?? wrapped.qualityProfiles ?? wrapped.results ?? wrapped.data ?? []
                return .success(resolved)
            } catch {
                return .failure(ProbeError(message: "Seerr responded, but Swiftfin could not read available profiles."))
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    private static func request(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) async -> Result<(Data, HTTPURLResponse), ProbeError> {
        let credentialsResult = credentials()
        guard case let .success(credentials) = credentialsResult else {
            if case let .failure(error) = credentialsResult {
                return .failure(error)
            }
            return .failure(ProbeError(message: "Seerr configuration is invalid."))
        }

        guard var components = URLComponents(url: apiURL(path, baseURL: credentials.serverURL), resolvingAgainstBaseURL: false) else {
            return .failure(ProbeError(message: "Enter a valid Seerr server URL."))
        }
        let filteredQueryItems = queryItems.filter { !($0.value?.isEmpty ?? true) }
        if !filteredQueryItems.isEmpty {
            components.queryItems = filteredQueryItems
        }
        guard let url = components.url else {
            return .failure(ProbeError(message: "Enter a valid Seerr server URL."))
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let apiKey = credentials.apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return .failure(ProbeError(message: "Seerr returned an unexpected response."))
            }

            return .success((data, http))
        } catch {
            return .failure(ProbeError(message: "Unable to reach Seerr: \(error.localizedDescription)"))
        }
    }

    private static func credentials() -> Result<Credentials, ProbeError> {
        let serverURLString = SeerrIntegration.serverURLString

        guard !serverURLString.isEmpty else {
            return .failure(ProbeError(message: "Provide a Seerr server URL."))
        }

        guard let serverURL = SeerrIntegration.serverURL else {
            return .failure(ProbeError(message: "Enter a valid Seerr server URL."))
        }

        let trimmedAPIKey = SeerrIntegration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAPIKey?.isEmpty ?? true {
            return .failure(ProbeError(message: "Provide a Seerr API key."))
        }

        return .success(Credentials(serverURL: serverURL, apiKey: trimmedAPIKey))
    }

    private struct Credentials {
        let serverURL: URL
        let apiKey: String?
    }

    static func tmdbImageURL(path: String?, size: TMDBImageSize = .original) -> URL? {
        guard let path, !path.isEmpty else { return nil }

        return URL(string: "https://image.tmdb.org/t/p/\(size.rawValue)\(path)")
    }

    private static func apiURL(_ path: String, baseURL: URL) -> URL {
        path
            .split(separator: "/")
            .reduce(baseURL.appendingPathComponent("api").appendingPathComponent("v1")) { partialResult, component in
                partialResult.appendingPathComponent(String(component))
            }
    }
}
