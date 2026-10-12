//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftUI

/// The DC color used by the preserved cinematic gradients. BlurHashKit 2 renders
/// hashes directly and no longer exposes the decoded BlurHash model.
struct PlatformBlurHash {
    private let linearRGB: (Float, Float, Float)

    init?(string: String) {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")
        let characters = Array(string)
        guard characters.count >= 6 else { return nil }

        let values = characters.compactMap { alphabet.firstIndex(of: $0) }
        guard values.count == characters.count else { return nil }

        let componentCount = (values[0] % 9 + 1) * (values[0] / 9 + 1)
        guard values.count == 4 + 2 * componentCount else { return nil }

        let dc = values[2 ..< 6].reduce(0) { $0 * 83 + $1 }
        func linear(_ channel: Int) -> Float {
            let value = Float(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        linearRGB = (linear(dc >> 16), linear((dc >> 8) & 255), linear(dc & 255))
    }

    var averageLinearColor: Color {
        Color(red: Double(linearRGB.0), green: Double(linearRGB.1), blue: Double(linearRGB.2))
    }
}
