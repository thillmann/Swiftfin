//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum SeerClient {
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
        let voteAverage: Double?
        let mediaInfo: MediaInfo?

        var posterImageSource: ImageSource {
            ImageSource(url: SeerClient.tmdbImageURL(path: posterPath, size: .w500))
        }

        var backdropImageSource: ImageSource {
            ImageSource(url: SeerClient.tmdbImageURL(path: backdropPath, size: .w1280))
        }
    }

    struct MediaInfo: Decodable, Equatable {
        let status: Int?
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
                return .failure(ProbeError(message: "Seer rejected the API key."))
            default:
                return .failure(ProbeError(message: "Seer status failed with HTTP \(http.statusCode)."))
            }

            do {
                let status = try JSONDecoder().decode(Status.self, from: data)
                return .success(status)
            } catch {
                return .failure(ProbeError(message: "Seer responded, but Swiftfin could not read the status."))
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
            failurePrefix: "Seer search failed"
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
            failurePrefix: "Seer discover movies failed"
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
            failurePrefix: "Seer discover TV failed"
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
            failurePrefix: "Seer upcoming movies failed"
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
            failurePrefix: "Seer upcoming TV failed"
        )
    }

    static func request(
        mediaType: RequestMediaType,
        mediaID: Int,
        seasons: [Int]? = nil,
        is4K: Bool? = nil
    ) async -> Result<Void, ProbeError> {
        struct RequestPayload: Encodable {
            let mediaType: String
            let mediaID: Int
            let seasons: [Int]?
            let is4K: Bool?

            enum CodingKeys: String, CodingKey {
                case mediaType
                case mediaID = "mediaId"
                case seasons
                case is4K = "is4k"
            }
        }

        let payload = RequestPayload(
            mediaType: mediaType.rawValue,
            mediaID: mediaID,
            seasons: seasons,
            is4K: is4K
        )

        let payloadData: Data
        do {
            payloadData = try JSONEncoder().encode(payload)
        } catch {
            return .failure(ProbeError(message: "Swiftfin could not create a Seer request payload."))
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
                return .failure(ProbeError(message: "Seer rejected the API key."))
            default:
                return .failure(ProbeError(message: "Seer request failed with HTTP \(http.statusCode)."))
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
                    return .failure(ProbeError(message: "Seer rejected the API key."))
                }
                return .failure(ProbeError(message: "\(failurePrefix) with HTTP \(http.statusCode)."))
            }

            do {
                return try .success(JSONDecoder().decode(T.self, from: data))
            } catch {
                return .failure(ProbeError(message: "Seer responded, but Swiftfin could not read the response."))
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
            return .failure(ProbeError(message: "Seer configuration is invalid."))
        }

        guard var components = URLComponents(url: apiURL(path, baseURL: credentials.serverURL), resolvingAgainstBaseURL: false) else {
            return .failure(ProbeError(message: "Enter a valid Seer server URL."))
        }
        let filteredQueryItems = queryItems.filter { !($0.value?.isEmpty ?? true) }
        if !filteredQueryItems.isEmpty {
            components.queryItems = filteredQueryItems
        }
        guard let url = components.url else {
            return .failure(ProbeError(message: "Enter a valid Seer server URL."))
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
                return .failure(ProbeError(message: "Seer returned an unexpected response."))
            }

            return .success((data, http))
        } catch {
            return .failure(ProbeError(message: "Unable to reach Seer: \(error.localizedDescription)"))
        }
    }

    private static func credentials() -> Result<Credentials, ProbeError> {
        let serverURLString = SeerrIntegration.serverURLString

        guard !serverURLString.isEmpty else {
            return .failure(ProbeError(message: "Provide a Seer server URL."))
        }

        guard let serverURL = SeerrIntegration.serverURL else {
            return .failure(ProbeError(message: "Enter a valid Seer server URL."))
        }

        let trimmedAPIKey = SeerrIntegration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAPIKey?.isEmpty ?? true {
            return .failure(ProbeError(message: "Provide a Seer API key."))
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
