//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftUI

extension DownloadTaskView {

    struct ContentView: View {

        @Injected(\.downloadManager)
        private var downloadManager

        @Router
        private var router

        @ObservedObject
        var downloadTask: DownloadTask

        private var controlState: DownloadControlState {
            downloadTask.state.controlState
        }

        private var actionTitle: String {
            switch downloadTask.state {
            case .complete:
                L10n.removeDownload
            case .downloading, .paused, .resolving:
                L10n.stopDownload
            case .error:
                L10n.retryDownload
            case .cancelled, .ready:
                L10n.download
            }
        }

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Button(action: showDetails) {
                        HStack(spacing: 16) {
                            artwork
                                .aspectRatio(2 / 3, contentMode: .fill)
                                .frame(width: 88, height: 132)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 6) {
                                Text(downloadTask.item.displayTitle)
                                    .font(.title3)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)

                                metadata

                                if downloadTask.state.isActive {
                                    Text(downloadTask.transferProgressText)
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: 8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    statusControl
                }

                Divider()
                    .padding(.leading, 120)

                if case let .error(error) = downloadTask.state {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                }

                if case .complete = downloadTask.state {
                    Button(L10n.play, systemImage: "play.fill", action: play)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }

        @ViewBuilder
        private var artwork: some View {
            if let record = downloadTask.record,
               let imageURL = DownloadStorage.imageURL(for: record, type: .primary)
            {
                ImageView(imageURL)
            } else {
                ImageView(downloadTask.item.portraitImageSources(maxWidth: 240))
            }
        }

        @ViewBuilder
        private var metadata: some View {
            DotHStack {
                if let firstGenre = downloadTask.item.genres?.first {
                    Text(firstGenre)
                }
                if let productionYear = downloadTask.item.premiereDateYear {
                    Text(productionYear)
                }
                if let runtime = downloadTask.item.runTimeLabel {
                    Text(runtime)
                }
                if let fileSize = downloadTask.expectedFileSizeText {
                    Text(fileSize)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        @ViewBuilder
        private var statusControl: some View {
            if case .complete = downloadTask.state {
                Menu {
                    Button(L10n.removeDownload, systemImage: "trash", role: .destructive) {
                        downloadManager.delete(task: downloadTask)
                        router.dismiss()
                    }
                } label: {
                    DownloadStatusIndicator(state: .complete, size: 40)
                }
            } else {
                DownloadStatusControl(state: controlState, size: 40) {
                    performDownloadAction()
                }
                .accessibilityLabel(actionTitle)
            }
        }

        private func showDetails() {
            if case .complete = downloadTask.state,
               let record = downloadTask.record
            {
                router.route(to: .downloadedItem(record: record))
            } else {
                router.route(to: .item(item: downloadTask.item))
            }
        }

        private func play() {
            guard case .complete = downloadTask.state,
                  let record = downloadTask.record
            else { return }

            router.route(to: .videoPlayer(downloadRecord: record))
        }

        private func performDownloadAction() {
            switch downloadTask.state {
            case .downloading, .paused, .resolving:
                downloadManager.cancel(task: downloadTask)
            case .error, .cancelled:
                downloadManager.retry(task: downloadTask)
            case .ready:
                downloadManager.download(task: downloadTask)
            case .complete:
                break
            }
        }
    }
}

private extension DownloadTask.State {

    var isActive: Bool {
        switch self {
        case .downloading, .paused, .resolving:
            true
        case .cancelled, .complete, .error, .ready:
            false
        }
    }
}
