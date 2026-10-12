//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

#if os(iOS)
private let buttonHeight: CGFloat = 44
private let buttonMaxSize: CGFloat = 300
private let iconSize: CGFloat = 72
#else
private let buttonHeight: CGFloat = 75
private let buttonMaxSize: CGFloat = 600
private let iconSize: CGFloat = 144
#endif

struct ErrorView<ErrorType: Error>: View {

    @Default(.accentColor)
    private var accentColor

    @Environment(\.refresh)
    private var refresh

    let error: ErrorType

    private var networkFailure: NetworkFailure? {
        if let errorMessage = error as? ErrorMessage {
            return errorMessage.networkFailure
        }

        return error.networkFailure
    }

    private var systemImage: String {
        if networkFailure != nil {
            return "wifi.slash"
        }

        if let error = error as? SystemImageable {
            return error.systemImage
        } else {
            return "xmark.circle"
        }
    }

    private var title: String {
        networkFailure == nil ? error.localizedDescription : L10n.connectionFailed
    }

    private var recoverySuggestion: String? {
        if let networkFailure {
            return networkFailure.message
        }

        return (error as? LocalizedError)?.recoverySuggestion
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(Color.red)
                .symbolRenderingMode(.monochrome)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let recoverySuggestion {
                    Text(recoverySuggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                }
            }

            if let refresh {
                Button {
                    Task {
                        await refresh()
                    }
                } label: {
                    Text(L10n.retry)
                        .frame(maxWidth: .infinity)
                }
                .fontWeight(.semibold)
                .backport
                .buttonStyle(.glassProminent.shadow(false))
                .tint(accentColor)
                #if os(iOS)
                    .controlSize(.large)
                #endif
                    .frame(height: buttonHeight)
                    .frame(maxWidth: buttonMaxSize)
            }
        }
        .frame(maxWidth: 600, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .focusSection()
        .edgePadding()
    }
}
