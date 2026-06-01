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
import SwiftUI

#if os(tvOS)
struct SeerSettingsView: View {

    @Default(.Integrations.Seerr.isEnabled)
    private var isEnabled

    @Default(.Integrations.Seerr.serverURL)
    private var serverURL

    @Injected(\.keychainService)
    private var keychain

    @State
    private var apiKey = ""

    @State
    private var probeState = ProbeState.idle

    @State
    private var statusState = StatusState.idle

    var body: some View {
        Form(systemImage: "server.rack") {
            Section("Seer") {
                LabeledContent(L10n.name, value: "Seer")
                #if os(tvOS)
                    .focusable(false)
                #endif

                switch statusState {
                case let .loaded(status):
                    LabeledContent(L10n.version, value: status.displayVersion)
                    #if os(tvOS)
                        .focusable(false)
                    #endif

                case .loading:
                    LabeledContent(L10n.status, value: "Checking...")
                    #if os(tvOS)
                        .focusable(false)
                    #endif

                case .failed:
                    LabeledContent(L10n.status, value: "Unavailable")
                    #if os(tvOS)
                        .focusable(false)
                    #endif

                case .idle:
                    EmptyView()
                }
            }

            Section {
                TextField("Server URL", text: $serverURL)
                    .textContentType(.URL)
            } header: {
                Text(L10n.serverURL)
            }

            Section {
                SecureField("API key", text: $apiKey)
                    .textContentType(.password)
            } header: {
                Text("API")
            } footer: {
                Text(probeFooter)
            }

            Section {
                Toggle("Enable Seer", isOn: integrationBinding)
                    .disabled(!canValidate || probeState == .validating)
            }
        }
        .navigationTitle("Seer")
        .onAppear(perform: loadAPIKey)
        .onChange(of: serverURL, perform: configurationDidChange)
        .onChange(of: apiKey, perform: saveAPIKey)
        .task(id: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) {
            await loadStatus()
        }
    }

    private var integrationBinding: Binding<Bool> {
        Binding(
            get: {
                isEnabled || probeState == .validating
            },
            set: { newValue in
                if newValue {
                    validateAndEnable()
                } else {
                    isEnabled = false
                    probeState = .idle
                }
            }
        )
    }

    private var canValidate: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var seerVersion: String? {
        guard case let .loaded(status) = statusState else {
            return nil
        }

        return status.displayVersion
    }

    private var probeFooter: String {
        switch probeState {
        case .idle:
            "Provide a Seer server URL and API key to enable the integration."
        case .validating:
            "Validating the Seer connection..."
        case .succeeded:
            if let seerVersion {
                "Seer \(seerVersion) is enabled and the connection was validated."
            } else {
                "Seer is enabled and the connection was validated."
            }
        case let .failed(message):
            message
        }
    }

    private func loadAPIKey() {
        apiKey = SeerrIntegration.apiKey ?? ""
    }

    private func configurationDidChange(_: String) {
        guard isEnabled || probeState != .idle else { return }

        isEnabled = false
        probeState = .idle
    }

    private func saveAPIKey(_ newValue: String) {
        let storedValue = SeerrIntegration.apiKey ?? ""
        let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedValue.isEmpty {
            keychain.delete(SeerrIntegration.apiKeyKeychainKey)
            isEnabled = false
            probeState = .idle
        } else {
            keychain.set(trimmedValue, forKey: SeerrIntegration.apiKeyKeychainKey)

            if isEnabled, trimmedValue != storedValue {
                isEnabled = false
                probeState = .idle
            } else if case .failed = probeState, trimmedValue != storedValue {
                probeState = .idle
            }
        }
    }

    @MainActor
    private func loadStatus() async {
        guard !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusState = .idle
            return
        }

        statusState = .loading

        do {
            try await Task.sleep(nanoseconds: 400_000_000)
        } catch {
            return
        }

        let result = await SeerClient.status()

        switch result {
        case let .success(status):
            statusState = .loaded(status)
        case .failure:
            statusState = .failed
        }
    }

    private func validateAndEnable() {
        let trimmedServerURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedServerURL.isEmpty, !trimmedAPIKey.isEmpty else {
            isEnabled = false
            probeState = .idle
            return
        }

        if serverURL != trimmedServerURL {
            serverURL = trimmedServerURL
        }

        keychain.set(trimmedAPIKey, forKey: SeerrIntegration.apiKeyKeychainKey)
        probeState = .validating

        Task {
            let result = await SeerClient.probe()

            await MainActor.run {
                switch result {
                case .success:
                    isEnabled = true
                    probeState = .succeeded
                    Task {
                        await loadStatus()
                    }

                case let .failure(error):
                    isEnabled = false
                    probeState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private enum StatusState: Equatable {
        case idle
        case loading
        case loaded(SeerClient.Status)
        case failed
    }

    private enum ProbeState: Equatable {
        case idle
        case validating
        case succeeded
        case failed(String)
    }
}

private extension SeerClient.Status {

    var displayVersion: String {
        version ?? appData?.version ?? L10n.unknown
    }
}
#endif
