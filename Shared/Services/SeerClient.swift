//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum SeerClient {

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
        let serverURLString = SeerrIntegration.serverURLString

        guard !serverURLString.isEmpty else {
            return .failure(ProbeError(message: "Provide a Seer server URL."))
        }

        guard let serverURL = SeerrIntegration.serverURL else {
            return .failure(ProbeError(message: "Enter a valid Seer server URL."))
        }

        var request = URLRequest(url: apiURL("status", baseURL: serverURL))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return .failure(ProbeError(message: "Seer returned an unexpected response."))
            }

            guard (200 ... 299).contains(http.statusCode) else {
                return .failure(ProbeError(message: "Seer status failed with HTTP \(http.statusCode)."))
            }

            do {
                let status = try JSONDecoder().decode(Status.self, from: data)
                return .success(status)
            } catch {
                return .failure(ProbeError(message: "Seer responded, but Swiftfin could not read the status."))
            }
        } catch {
            return .failure(ProbeError(message: "Unable to reach Seer: \(error.localizedDescription)"))
        }
    }

    static func probe() async -> Result<Void, ProbeError> {
        let serverURLString = SeerrIntegration.serverURLString

        guard !serverURLString.isEmpty else {
            return .failure(ProbeError(message: "Provide a Seer server URL to enable the integration."))
        }

        guard let serverURL = SeerrIntegration.serverURL else {
            return .failure(ProbeError(message: "Enter a valid Seer server URL."))
        }

        guard let apiKey = SeerrIntegration.apiKey else {
            return .failure(ProbeError(message: "Provide a Seer API key to enable the integration."))
        }

        var request = URLRequest(url: apiURL("settings/main", baseURL: serverURL))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return .failure(ProbeError(message: "Seer returned an unexpected response."))
            }

            switch http.statusCode {
            case 200 ... 299:
                return .success(())
            case 401, 403:
                return .failure(ProbeError(message: "Seer rejected the API key."))
            default:
                return .failure(ProbeError(message: "Seer connection failed with HTTP \(http.statusCode)."))
            }
        } catch {
            return .failure(ProbeError(message: "Unable to reach Seer: \(error.localizedDescription)"))
        }
    }

    private static func apiURL(_ path: String, baseURL: URL) -> URL {
        path
            .split(separator: "/")
            .reduce(baseURL.appendingPathComponent("api").appendingPathComponent("v1")) { partialResult, component in
                partialResult.appendingPathComponent(String(component))
            }
    }
}
