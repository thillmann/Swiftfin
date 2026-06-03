//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

enum FeatureButtonTokens {
    static let baseHeight: CGFloat = 64

    static let unfocusedBorderOpacity: CGFloat = 0.2
}

extension ButtonStyle where Self == FeatureButtonStyle {
    static var featureButton: FeatureButtonStyle {
        FeatureButtonStyle(height: FeatureButtonTokens.baseHeight)
    }

    static var featureIconButton: FeatureButtonStyle {
        FeatureButtonStyle(diameter: FeatureButtonTokens.baseHeight)
    }
}

struct FeatureButtonStyle: ButtonStyle {

    enum Variant {
        case pill(height: CGFloat)
        case icon(diameter: CGFloat)
    }

    @Environment(\.isEnabled)
    private var isEnabled
    @Environment(\.isFocused)
    private var isFocused

    let variant: Variant
    let isFocusedOverride: Bool?

    init(height: CGFloat, isFocusedOverride: Bool? = nil) {
        self.variant = .pill(height: height)
        self.isFocusedOverride = isFocusedOverride
    }

    init(diameter: CGFloat, isFocusedOverride: Bool? = nil) {
        self.variant = .icon(diameter: diameter)
        self.isFocusedOverride = isFocusedOverride
    }

    func makeBody(configuration: Configuration) -> some View {
        let effectiveFocus = isFocusedOverride ?? isFocused

        switch variant {
        case let .pill(height):
            configuration.label
                .foregroundStyle(foregroundColor(isFocused: effectiveFocus, variant: variant))
                .symbolRenderingMode(.monochrome)
                .frame(height: height)
                .background(
                    Capsule(style: .continuous)
                        .fill(backgroundColor(isFocused: effectiveFocus))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(borderColor(isFocused: effectiveFocus), lineWidth: 1)
                }
                .opacity(isEnabled ? 1 : 0.62)
                .animation(.easeOut(duration: 0.12), value: effectiveFocus)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        case let .icon(diameter):
            configuration.label
                .foregroundStyle(foregroundColor(isFocused: effectiveFocus, variant: variant))
                .symbolRenderingMode(.monochrome)
                .frame(width: diameter, height: diameter)
                .background(
                    Circle()
                        .fill(backgroundColor(isFocused: effectiveFocus))
                )
                .overlay {
                    Circle()
                        .stroke(borderColor(isFocused: effectiveFocus), lineWidth: 1)
                }
                .opacity(isEnabled ? 1 : 0.62)
                .animation(.easeOut(duration: 0.12), value: effectiveFocus)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    private func foregroundColor(isFocused: Bool, variant: Variant) -> Color {
        if isFocused {
            return Color(red: 0.05, green: 0.05, blue: 0.05)
        }

        switch variant {
        case .pill:
            return .white
        case .icon:
            return .white.opacity(0.96)
        }
    }

    private func backgroundColor(isFocused: Bool) -> Color {
        if isFocused {
            return Color(red: 0.92, green: 0.92, blue: 0.93)
        }
        return .black.opacity(0.24)
    }

    private func borderColor(isFocused: Bool) -> Color {
        if isFocused {
            return .white.opacity(0.14)
        }
        return .white.opacity(FeatureButtonTokens.unfocusedBorderOpacity)
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
                    let fillWidth = proxy.size.width * value

                    if fillWidth > 0 {
                        Capsule(style: .continuous)
                            .fill(fillColor)
                            .frame(width: fillWidth)
                    }
                }
                .clipShape(Capsule(style: .continuous))
            }
        }
        .frame(height: height)
        .shadow(color: .clear, radius: 0) // explicit: no shadow
        .accessibilityValue(Text("\(Int(value * 100))%"))
    }
}

#if DEBUG
private struct FeatureButtonStylesPreview: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Feature Button")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 20) {
                    previewFeatureButton(title: "Play", focused: true)
                    previewFeatureButton(title: "Play", focused: false)
                    previewFeatureButton(title: "Play", focused: false, isEnabled: false)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Inline Progress Button")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 20) {
                    previewInlineProgressButton(focused: true)
                    previewInlineProgressButton(focused: false)
                    previewInlineProgressButton(focused: false, isEnabled: false)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Icon-only Button")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 20) {
                    previewIconButton(icon: "heart", focused: true)
                    previewIconButton(icon: "heart", focused: false)
                    previewIconButton(icon: "heart.fill", focused: false, isEnabled: false)
                }
            }
        }
        .padding(40)
        .background(Color.black)
    }

    @ViewBuilder
    private func previewFeatureButton(
        title: String,
        focused: Bool,
        isEnabled: Bool = true
    ) -> some View {
        Button {
            // preview only
        } label: {
            Label(title, systemImage: "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .padding(.horizontal, 40)
                .frame(maxHeight: .infinity)
        }
        .buttonStyle(
            FeatureButtonStyle(
                height: FeatureButtonTokens.baseHeight,
                isFocusedOverride: focused
            )
        )
        .frame(height: FeatureButtonTokens.baseHeight)
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private func previewInlineProgressButton(
        focused: Bool,
        isEnabled: Bool = true
    ) -> some View {
        Button {
            // preview only
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .semibold))

                ProgressView(value: 0.56)
                    .progressViewStyle(
                        FeatureInlineProgressStyle(
                            trackColor: focused ? .black.opacity(0.2) : .white.opacity(0.2),
                            fillColor: focused ? .black : .white
                        )
                    )
                    .frame(width: 60)

                Text("54m")
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 40)
        }
        .buttonStyle(
            FeatureButtonStyle(
                height: FeatureButtonTokens.baseHeight,
                isFocusedOverride: focused
            )
        )
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private func previewIconButton(
        icon: String,
        focused: Bool,
        isEnabled: Bool = true
    ) -> some View {
        Button {
            // preview only
        } label: {
            Image(systemName: icon)
                .font(.system(size: FeatureButtonTokens.baseHeight * 0.4, weight: .semibold))
        }
        .buttonStyle(
            FeatureButtonStyle(
                diameter: FeatureButtonTokens.baseHeight,
                isFocusedOverride: focused
            )
        )
        .frame(width: FeatureButtonTokens.baseHeight, height: FeatureButtonTokens.baseHeight)
        .disabled(!isEnabled)
    }
}

#Preview("Button", traits: .sizeThatFitsLayout) {
    FeatureButtonStylesPreview()
}
#endif
