//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation

/// Persists local playback without issuing Jellyfin session requests. Pending
/// progress is synchronized later by `DownloadManager` when the app reconnects.
final class OfflineMediaProgressObserver: ViewModel, MediaPlayerObserver {

    weak var manager: MediaPlayerManager? {
        didSet {
            guard let manager else { return }
            setup(with: manager)
        }
    }

    private let recordID: String
    private weak var item: MediaPlayerItem?
    private let timer = PokeIntervalTimer()

    init(item: MediaPlayerItem, recordID: String) {
        self.item = item
        self.recordID = recordID
        super.init()
    }

    private func setup(with manager: MediaPlayerManager) {
        cancellables = []
        timer.sink { [weak self] in
            self?.saveProgress()
            self?.timer.poke()
        }
        .store(in: &cancellables)

        manager.actions
            .sink { [weak self] action in
                switch action {
                case .ended:
                    self?.saveProgress(forcePlayed: true)
                case .stop:
                    self?.saveProgress()
                    self?.timer.stop()
                default:
                    break
                }
            }
            .store(in: &cancellables)

        timer.poke()
    }

    private func saveProgress(forcePlayed: Bool = false) {
        guard let item, let position = manager?.seconds else { return }
        let played: Bool = {
            if forcePlayed { return true }
            guard let runtime = item.baseItem.runtime, runtime > .zero else { return false }
            return Double(position.ticks) / Double(runtime.ticks) >= 0.9
        }()

        Container.shared.downloadManager().saveOfflineProgress(
            recordID: recordID,
            positionTicks: position.ticks,
            isPlayed: played
        )
    }
}
