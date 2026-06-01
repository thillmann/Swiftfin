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
struct SeerrSettingsView: View {

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

    @State
    private var isPresentingServerURLEditor = false

    @State
    private var editableServerURL = ""

    @State
    private var isPresentingAPIKeyEditor = false

    @State
    private var editableAPIKey = ""

    var body: some View {
        Form(systemImage: "server.rack") {
            Section("Seerr") {
                LabeledContent(L10n.name, value: "Seerr")
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
                ChevronButton(L10n.url, action: presentServerURLEditor) {
                    Text(serverURLDisplay)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: {
                Text(L10n.serverURL)
            }

            Section {
                ChevronButton("API key", content: apiKeyDisplay, action: presentAPIKeyEditor)
            } header: {
                Text("Authentication")
            } footer: {
                Text(probeFooter)
            }

            Section {
                Toggle("Enable Seerr", isOn: integrationBinding)
                    .disabled(!canValidate || probeState == .validating)
            }
        }
        .navigationTitle("Seerr")
        .onAppear(perform: loadAPIKey)
        .onChange(of: serverURL, perform: configurationDidChange)
        .onChange(of: apiKey, perform: saveAPIKey)
        .task(id: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) {
            await loadStatus()
        }
        .alert(L10n.serverURL, isPresented: $isPresentingServerURLEditor) {
            TextField("http://", text: $editableServerURL)

            Button(L10n.save) {
                serverURL = editableServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text("Enter the Seerr server URL.")
        }
        .alert("API key", isPresented: $isPresentingAPIKeyEditor) {
            SecureField("API key", text: $editableAPIKey)

            Button(L10n.save) {
                apiKey = editableAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text("Enter the Seerr API key.")
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

    private var serverURLDisplay: String {
        let trimmedServerURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmedServerURL.isEmpty ? L10n.none : trimmedServerURL
    }

    private var apiKeyDisplay: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.none : "Configured"
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
            "Provide a Seerr server URL and API key to enable the integration."
        case .validating:
            "Validating the Seerr connection..."
        case .succeeded:
            if let seerVersion {
                "Seerr \(seerVersion) is enabled and the connection was validated."
            } else {
                "Seerr is enabled and the connection was validated."
            }
        case let .failed(message):
            message
        }
    }

    private func loadAPIKey() {
        apiKey = SeerrIntegration.apiKey ?? ""
    }

    private func presentServerURLEditor() {
        editableServerURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        isPresentingServerURLEditor = true
    }

    private func presentAPIKeyEditor() {
        editableAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isPresentingAPIKeyEditor = true
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

        let result = await SeerrClient.status()

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
            let result = await SeerrClient.status()

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
                    let errorMessage: String = if error.message.hasPrefix("Seerr status failed with HTTP ") {
                        error.message.replacingOccurrences(
                            of: "Seerr status failed",
                            with: "Seerr connection failed"
                        )
                    } else {
                        error.localizedDescription
                    }
                    probeState = .failed(errorMessage)
                }
            }
        }
    }

    private enum StatusState: Equatable {
        case idle
        case loading
        case loaded(SeerrClient.Status)
        case failed
    }

    private enum ProbeState: Equatable {
        case idle
        case validating
        case succeeded
        case failed(String)
    }
}

private extension SeerrClient.Status {

    var displayVersion: String {
        version ?? appData?.version ?? L10n.unknown
    }
}
#endif
