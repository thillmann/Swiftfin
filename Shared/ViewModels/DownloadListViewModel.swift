//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

class DownloadListViewModel: ViewModel {

    @Injected(\.downloadManager)
    private var downloadManager

    @Published
    var items: [DownloadTask] = []

    override init() {
        super.init()

        downloadManager.$downloads
            .sink { [weak self] downloads in
                // @Published emits the new value before the manager's stored
                // property changes, so derive the list from this snapshot.
                self?.items = self?.downloadManager.downloadedItems(from: downloads) ?? []
            }
            .store(in: &cancellables)
    }
}
