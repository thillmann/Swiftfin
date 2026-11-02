//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import SwiftUI

struct SettingsView: View {

    #if os(iOS)
    @Default(.userAppearance)
    private var appearance
    #endif

    @Default(.VideoPlayer.mediaPlayerType)
    private var videoPlayerType

    @Default(.userAccentColor)
    private var accentColor

    @InjectedObject(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    #if os(tvOS)
    @Default(.Integrations.Seerr.isEnabled)
    private var isSeerrIntegrationEnabled

    @Default(.Integrations.Seerr.serverURL)
    private var seerrServerURL
    #endif

    @Router
    private var router

    // MARK: - Body

    var body: some View {
        Form(image: .jellyfinBlobBlue) {
            serverSection
            videoPlayerSection
            #if os(tvOS)
            integrationsSection
            #endif
            customizeSection
            diagnosticsSection
        }
        #if os(iOS)
        .navigationTitle(L10n.settings)
        .navigationBarCloseButton {
            router.dismiss()
        }
        #endif
    }

    // MARK: - Server Section

    @ViewBuilder
    private var serverSection: some View {
        if let userSession = userSessionManager.currentSession {
            Section {
                UserProfileRow(user: userSession.user.data) {
                    router.route(to: .localUserSettings(user: userSession.user.data))
                }

                ChevronButton(
                    L10n.server,
                    action: {
                        router.route(to: .editLocalServer(server: userSession.server))
                    }
                ) {
                    Label {
                        Text(userSession.server.name)
                    } icon: {
                        if !userSession.server.isVersionCompatible {
                            Image(systemName: "exclamationmark.circle.fill")
                        }
                    }
                    .labelStyle(.sectionFooterWithImage(imageStyle: .orange))
                }

                #if os(iOS)
                if userSession.user.data.policy?.isAdministrator == true {
                    ChevronButton(L10n.dashboard) {
                        router.route(to: .adminDashboard)
                    }
                }
                #endif
            }
        }

        Section {
            Button {
                Task { @MainActor in
                    UIDevice.impact(.medium)
                    await userSessionManager.signOut(reason: .explicit)
                    router.dismiss()
                }
            } label: {
                Text(L10n.switchUser)
                    .frame(maxWidth: .infinity)
                    // Otherwise non-Liquid Glass only uses text height
                    .if(!UIDevice.supportsLiquidGlass) { button in
                        button
                            .frame(maxHeight: .infinity)
                    }
            }
            .listRowInsets(.zero)
            .listRowBackground(Color.clear)
            #if os(iOS)
                .listRowSeparator(.hidden)
            #endif
                .fontWeight(.semibold)
                .backport
                .buttonStyle(.glassProminent.shadow(false))
                .tint(accentColor)
            #if os(iOS)
                .controlSize(.large)
            #endif
        }
    }

    @ViewBuilder
    private var videoPlayerSection: some View {
        Section(L10n.videoPlayer) {
            #if os(iOS)
            Picker(L10n.videoPlayerType, selection: $videoPlayerType)
            #else
            ListRowMenu(L10n.videoPlayerType, selection: $videoPlayerType)
            #endif

            ChevronButton(L10n.videoPlayer) {
                router.route(to: .videoPlayerSettings)
            }

            ChevronButton(L10n.playbackQuality) {
                router.route(to: .playbackQualitySettings)
            }
        } learnMore: {
            LabeledContent(
                L10n.swiftfin,
                value: L10n.playerSwiftfinDescription
            )
            LabeledContent(
                L10n.native,
                value: L10n.playerNativeDescription
            )
            LabeledContent(
                L10n.aether,
                value: L10n.playerAetherDescription
            )
        }
    }

    #if os(tvOS)
    @ViewBuilder
    private var integrationsSection: some View {
        Section {
            ChevronButton(
                "Seerr",
                action: {
                    router.route(to: .seerSettings)
                }
            ) {
                Label {
                    Text(seerrIntegrationStatus)
                } icon: {
                    if SeerrIntegration.isAvailable {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
                .labelStyle(.sectionFooterWithImage(imageStyle: .green))
            }
        } header: {
            Text(L10n.integrations)
        }
    }

    private var seerrIntegrationStatus: String {
        let storedServerURL = seerrServerURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !storedServerURL.isEmpty,
              SeerrIntegration.isConfigured
        else {
            return L10n.notConfigured
        }

        return isSeerrIntegrationEnabled ? L10n.enabled : L10n.disabled
    }
    #endif

    // MARK: - Customization Section

    private var customizeSection: some View {
        Section {
            #if os(iOS)
            Picker(L10n.appearance, selection: $appearance)
            #endif

            ColorPicker(L10n.accentColor, selection: $accentColor, supportsOpacity: false)

            ChevronButton(L10n.advanced) {
                router.route(to: .customizeSettingsView)
            }
        } header: {
            Text(L10n.customize)
        } footer: {
            Text(L10n.viewsMayRequireRestart)
        }
    }

    // MARK: - Diagnostics Section

    private var diagnosticsSection: some View {
        Section {

            if ExperimentalSettingsView.isEnabled {
                ChevronButton(L10n.experimental) {
                    router.route(to: .experimentalSettings)
                }
            }

            ChevronButton(L10n.logs) {
                router.route(to: .log)
            }

            #if DEBUG
            ChevronButton("Debug") {
                router.route(to: .debugSettings)
            }
            #endif
        }
    }
}
