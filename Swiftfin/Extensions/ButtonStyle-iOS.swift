//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// - Important: On iOS, this is a `BorderlessButtonStyle` instead.
/// This is only used to allow platform shared views.
extension PrimitiveButtonStyle where Self == BorderlessButtonStyle {
    static var card: BorderlessButtonStyle {
        .init()
    }
}

extension ButtonStyle where Self == IsPressedButtonStyle {

    static func isPressed(_ isPressed: @escaping (Bool) -> Void) -> IsPressedButtonStyle {
        IsPressedButtonStyle(isPressed: isPressed)
    }
}

struct IsPressedButtonStyle: ButtonStyle {

    let isPressed: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) {
                isPressed(configuration.isPressed)
            }
    }
}

// Matches the prominent action treatment used by the tvOS cinematic hero.
enum FeatureButtonTokens {
    static let baseHeight: CGFloat = 48
    static let labelFont: Font = .headline
    static let actionSpacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 22
}

extension ButtonStyle where Self == FeatureButtonStyle {
    static var featureButton: FeatureButtonStyle {
        FeatureButtonStyle(variant: .pill, isHighlighted: true)
    }

    static var featureIconButton: FeatureButtonStyle {
        FeatureButtonStyle(variant: .icon, isHighlighted: false)
    }
}

struct FeatureInlineProgressStyle: ProgressViewStyle {
    var height: CGFloat = 8
    var trackColor: Color = .white.opacity(0.22)
    var fillColor: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        let value = min(max(configuration.fractionCompleted ?? 0, 0), 1)

        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(trackColor)

            if value > 0 {
                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(fillColor)
                        .frame(width: proxy.size.width * value)
                }
                .clipShape(Capsule(style: .continuous))
            }
        }
        .frame(height: height)
        .accessibilityValue(Text("\(Int(value * 100))%"))
    }
}

struct FeatureButtonStyle: ButtonStyle {

    enum Variant {
        case pill
        case icon
    }

    @Environment(\.isEnabled)
    private var isEnabled

    let variant: Variant
    let isHighlighted: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        switch variant {
        case .pill:
            buttonBody(configuration: configuration, shape: Capsule(style: .continuous))
        case .icon:
            buttonBody(
                configuration: configuration,
                shape: Circle(),
                width: FeatureButtonTokens.baseHeight
            )
        }
    }

    private func buttonBody(
        configuration: Configuration,
        shape: some InsettableShape,
        width: CGFloat? = nil
    ) -> some View {
        let isActive = isHighlighted || configuration.isPressed

        return configuration.label
            .foregroundStyle(isActive ? Color.black : .white)
            .symbolRenderingMode(.monochrome)
            .frame(width: width, height: FeatureButtonTokens.baseHeight)
            .background {
                shape.fill(isActive ? Color(red: 0.92, green: 0.92, blue: 0.93) : .black.opacity(0.24))
            }
            .overlay {
                shape.stroke(.white.opacity(isActive ? 0.14 : 0.2), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.62)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: isActive)
    }
}
