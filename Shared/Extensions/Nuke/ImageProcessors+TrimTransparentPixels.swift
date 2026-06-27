//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Nuke
import UIKit

#if os(tvOS)
extension ImageProcessors {

    struct TrimTransparentPixels: ImageProcessing, Hashable {

        let alphaThreshold: UInt8

        init(alphaThreshold: UInt8 = 16) {
            self.alphaThreshold = alphaThreshold
        }

        var identifier: String {
            "com.swiftfin.trim-transparent-pixels-\(alphaThreshold)"
        }

        func process(_ image: UIImage) -> UIImage? {
            image.trimmedTransparentPixels(alphaThreshold: alphaThreshold)
        }
    }
}
#endif
