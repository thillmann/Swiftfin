//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI
import SwiftUIIntrospect

extension View {

    /// - Important: This does nothing on tvOS.
    @ViewBuilder
    func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View {
        self
    }

    /// - Important: This does nothing on tvOS.
    @ViewBuilder
    func navigationBarCloseButton(
        disabled: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        self
    }

    /// - Important: This does nothing on tvOS.
    @ViewBuilder
    func statusBarHidden() -> some View {
        self
    }

    /// - Important: This does nothing on tvOS.
    @ViewBuilder
    func prefersStatusBarHidden(_ hidden: Bool = true) -> some View {
        self
    }

    func glassLift(
        in shape: some InsettableShape,
        isFocused: Bool? = nil,
        scale: CGFloat = 1.06,
        shadowOpacity: Double = 0.28,
        shadowRadius: CGFloat = 12,
        shadowY: CGFloat = 7,
        highlightOpacity: Double = 0.86,
        sideHighlightOpacity: Double = 0.16,
        animation: Animation = .easeInOut(duration: 0.15)
    ) -> some View {
        modifier(
            GlassLiftModifier(
                shape: shape,
                isFocusedOverride: isFocused,
                scale: scale,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY,
                highlightOpacity: highlightOpacity,
                sideHighlightOpacity: sideHighlightOpacity,
                animation: animation
            )
        )
    }
}

extension EnvironmentValues {

    @Entry
    var presentationCoordinator: PresentationCoordinator = .init()
}

struct PresentationCoordinator {
    var isPresented: Bool = false
}

struct FocusNeutralButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == FocusNeutralButtonStyle {

    static var focusNeutral: FocusNeutralButtonStyle {
        FocusNeutralButtonStyle()
    }
}

private struct GlassLiftModifier<S: InsettableShape>: ViewModifier {

    @Environment(\.isFocused)
    private var isEnvironmentFocused

    let shape: S
    let isFocusedOverride: Bool?
    let scale: CGFloat
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    let highlightOpacity: Double
    let sideHighlightOpacity: Double
    let animation: Animation

    private var isFocused: Bool {
        isFocusedOverride ?? isEnvironmentFocused
    }

    func body(content: Content) -> some View {
        content
            .clipShape(shape)
            .contentShape(shape)
            .overlay {
                shape
                    .strokeBorder(.black.opacity(isFocused ? 0.18 : 0.10), lineWidth: 1)
            }
            .overlay {
                shape
                    .strokeBorder(.white.opacity(isFocused ? 0.18 : 0.08), lineWidth: 1)
            }
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isFocused ? highlightOpacity : 0), location: 0),
                                .init(color: .white.opacity(isFocused ? 0.46 : 0.06), location: 0.08),
                                .init(color: .white.opacity(isFocused ? 0.16 : 0.04), location: 0.26),
                                .init(color: .clear, location: 0.52),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isFocused ? 2 : 1
                    )
            }
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isFocused ? sideHighlightOpacity : 0), location: 0),
                                .init(color: .clear, location: 0.12),
                                .init(color: .clear, location: 0.88),
                                .init(color: .white.opacity(isFocused ? sideHighlightOpacity * 0.85 : 0), location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            }
            .scaleEffect(isFocused ? scale : 1)
            .shadow(
                color: .black.opacity(isFocused ? shadowOpacity : 0),
                radius: shadowRadius,
                y: shadowY
            )
            .animation(animation, value: isFocused)
    }
}
