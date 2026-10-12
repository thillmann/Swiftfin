//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Observable UI adapter around the durable `DownloadRecord` owned by
/// `DownloadManager`. Transfer work intentionally does not live in this type,
/// so it can be reconstructed after an app relaunch.
final class DownloadTask: ObservableObject, Identifiable {

    enum State {
        case cancelled
        case complete
        case downloading(Double)
        case error(Error)
        case paused(Double)
        case ready
        case resolving

        var isInProgress: Bool {
            switch self {
            case .downloading, .paused, .resolving:
                true
            case .cancelled, .complete, .error, .ready:
                false
            }
        }

        func isUIEquivalent(to other: State) -> Bool {
            switch (self, other) {
            case (.cancelled, .cancelled), (.complete, .complete), (.ready, .ready), (.resolving, .resolving):
                true
            case let (.downloading(lhs), .downloading(rhs)), let (.paused(lhs), .paused(rhs)):
                lhs == rhs
            case let (.error(lhs), .error(rhs)):
                lhs.localizedDescription == rhs.localizedDescription
            default:
                false
            }
        }
    }

    @Published
    private(set) var state: State

    private(set) var record: DownloadRecord?
    let item: BaseItemDto
    let mediaSource: MediaSourceInfo?

    var id: String {
        record?.id ?? "pending-\(item.id ?? UUID().uuidString)-\(mediaSource?.id ?? "source")"
    }

    init(item: BaseItemDto, mediaSource: MediaSourceInfo? = nil, record: DownloadRecord? = nil) {
        self.item = item
        self.mediaSource = mediaSource
        self.record = record
        self.state = record.map(Self.state(for:)) ?? .ready
    }

    func update(record: DownloadRecord, forcePublication: Bool = false) {
        self.record = record
        let nextState = Self.state(for: record)
        if forcePublication || !state.isUIEquivalent(to: nextState) {
            state = nextState
        }
    }

    func getImageURL(name: String) -> URL? {
        guard let record else { return nil }
        return DownloadStorage.imageURL(for: record, name: name)
    }

    func getMediaURL() -> URL? {
        guard let record else { return nil }
        return DownloadStorage.mediaURL(for: record)
    }

    /// A clamped transfer fraction suitable for progress indicators.
    var transferProgress: Double {
        let progress: Double = switch state {
        case let .downloading(value), let .paused(value): value
        default: record?.progress ?? 0
        }
        return min(max(progress, 0), 1)
    }

    var transferPercentageText: String {
        transferProgress.formatted(.percent.precision(.fractionLength(0)))
    }

    /// Best available total size before, during, or after a transfer.
    var expectedByteCount: Int64? {
        let candidates = [
            record?.expectedBytes,
            mediaSource?.size.map(Int64.init),
            item.mediaSources?.first?.size.map(Int64.init),
        ]
        return candidates.compacted().first(where: { $0 > 0 })
    }

    var expectedFileSizeText: String? {
        expectedByteCount?.formatted(.byteCount(style: .file))
    }

    /// Compact progress shared by the toolbar, list, and detail views.
    /// A slash keeps the byte relationship language-neutral until every
    /// translation can provide a localized "of" format.
    var transferProgressText: String {
        guard let record else { return transferPercentageText }
        let bytesWritten = max(record.bytesWritten, 0)
        let transferred = bytesWritten.formatted(.byteCount(style: .file))

        if let expectedBytes = record.expectedBytes, expectedBytes > 0 {
            let total = expectedBytes.formatted(.byteCount(style: .file))
            return "\(transferPercentageText) · \(transferred) / \(total)"
        }
        if bytesWritten > 0 {
            return "\(transferPercentageText) · \(transferred)"
        }
        return transferPercentageText
    }

    private static func state(for record: DownloadRecord) -> State {
        switch record.status {
        case .completed:
            .complete
        case .downloading, .queued, .finalizing:
            .downloading(record.progress)
        case .paused:
            .paused(record.progress)
        case .failed:
            .error(ErrorMessage(record.errorDescription ?? "Download failed"))
        case .cancelled, .deleting:
            .cancelled
        case .resolving:
            .resolving
        }
    }
}
