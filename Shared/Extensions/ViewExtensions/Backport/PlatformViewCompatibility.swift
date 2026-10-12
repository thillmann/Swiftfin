//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension Backport where Content: View {
    func matchedTransitionSource(id: String, in namespace: Namespace.ID) -> some View {
        content.matchedTransitionSource(id: id, in: namespace)
    }

    func onChange<V: Equatable>(of value: V, _ action: @escaping (V, V) -> Void) -> some View {
        content.onChange(of: value, action)
    }

    func onChange(of value: some Equatable, _ action: @escaping () -> Void) -> some View {
        content.onChange(of: value, action)
    }

    func scrollClipDisabled(_ disabled: Bool = true) -> some View {
        content.scrollClipDisabled(disabled)
    }

    func toolbarTitleDisplayMode(_ mode: SwiftUI.ToolbarTitleDisplayMode) -> some View {
        content.toolbarTitleDisplayMode(mode)
    }

    func defaultFocus<V: Hashable>(
        _ binding: FocusState<V>.Binding,
        _ value: V,
        priority: DefaultFocusEvaluationPriority = .automatic
    ) -> some View {
        content.defaultFocus(binding, value, priority: priority)
    }

    func focusable(_ isFocusable: Bool = true) -> some View {
        content.focusable(isFocusable)
    }

    #if os(iOS)
    @available(tvOS, unavailable)
    func searchFocused(_ isSearchFocused: FocusState<Bool>.Binding) -> some View {
        content.searchFocused(isSearchFocused)
    }
    #endif

    @ViewBuilder
    func navigationTransition(_ style: NavigationTransition) -> some View {
        if case let .zoom(sourceID, namespace) = style {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}
