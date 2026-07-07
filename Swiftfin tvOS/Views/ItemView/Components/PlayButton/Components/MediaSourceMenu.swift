//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftUI

extension ItemView {

    struct MediaSourceMenu: View {

        fileprivate struct Option: Identifiable, Equatable {

            let id: String
            let index: Int
            let sourceID: String?
            let sourceETag: String?
            let title: String
        }

        @State
        private var isSelectorPresented = false

        @ObservedObject
        var viewModel: ItemViewModel

        private let mediaSources: [MediaSourceInfo]

        init(viewModel: ItemViewModel, mediaSources: [MediaSourceInfo]) {
            self.viewModel = viewModel
            self.mediaSources = mediaSources
        }

        // MARK: - Body

        var body: some View {
            Button {
                isSelectorPresented = true
            } label: {
                Image(systemName: "list.triangle")
            }
            .labelStyle(.iconOnly)
            .font(FeatureButtonTokens.labelFont)
            .buttonStyle(.featureIconButton)
            .accessibilityLabel(L10n.version)
            .sheet(isPresented: $isSelectorPresented) {
                MediaSourceSelector(
                    mediaSources: mediaSources,
                    selectedMediaSource: viewModel.selectedMediaSource
                ) { option in
                    select(option)
                }
            }
        }

        private func select(_ option: Option) {
            guard mediaSources.indices.contains(option.index) else { return }

            viewModel.send(.selectMediaSource(mediaSources[option.index]))
            isSelectorPresented = false
        }
    }
}

private struct MediaSourceSelector: View {

    @FocusState
    private var isSelectorFocused: Bool

    @State
    private var focusedIndex: Int

    private static let maximumVisibleOptions = 3
    private static let optionRowHeight: CGFloat = 168
    private static let selectorHeight: CGFloat = 700

    let options: [ItemView.MediaSourceMenu.Option]
    let selectedOptionID: String?
    let onSelect: (ItemView.MediaSourceMenu.Option) -> Void

    init(
        mediaSources: [MediaSourceInfo],
        selectedMediaSource: MediaSourceInfo?,
        onSelect: @escaping (ItemView.MediaSourceMenu.Option) -> Void
    ) {
        let options = Self.makeOptions(from: mediaSources)
        let selectedIndex = Self.selectedOptionIndex(
            for: selectedMediaSource,
            in: mediaSources,
            options: options
        )

        self.options = options
        self.selectedOptionID = selectedIndex.map { options[$0].id }
        self.onSelect = onSelect
        self._focusedIndex = State(initialValue: selectedIndex ?? 0)
    }

    private var clampedFocusedIndex: Int {
        guard options.isNotEmpty else { return 0 }

        return min(max(focusedIndex, 0), options.count - 1)
    }

    private var visibleRange: Range<Int> {
        guard options.isNotEmpty else { return 0 ..< 0 }

        let visibleCount = min(Self.maximumVisibleOptions, options.count)
        let halfVisibleCount = visibleCount / 2
        let maximumStartIndex = max(options.count - visibleCount, 0)
        let startIndex = min(max(clampedFocusedIndex - halfVisibleCount, 0), maximumStartIndex)

        return startIndex ..< (startIndex + visibleCount)
    }

    private var visibleOptions: [ItemView.MediaSourceMenu.Option] {
        Array(options[visibleRange])
    }

    private static func makeOptions(from mediaSources: [MediaSourceInfo]) -> [ItemView.MediaSourceMenu.Option] {
        mediaSources.enumerated().map { index, mediaSource in
            let title = sanitizedTitle(for: mediaSource)
            let identity = mediaSource.id ?? mediaSource.eTag ?? title

            return ItemView.MediaSourceMenu.Option(
                id: "\(index)-\(identity)",
                index: index,
                sourceID: mediaSource.id,
                sourceETag: mediaSource.eTag,
                title: title
            )
        }
    }

    private static func sanitizedTitle(for mediaSource: MediaSourceInfo) -> String {
        let titleLines = mediaSource.displayTitle
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(\.isNotEmpty)

        return titleLines.isEmpty ? mediaSource.displayTitle : titleLines.joined(separator: "\n")
    }

    private static func selectedOptionIndex(
        for selectedMediaSource: MediaSourceInfo?,
        in mediaSources: [MediaSourceInfo],
        options: [ItemView.MediaSourceMenu.Option]
    ) -> Int? {
        guard options.isNotEmpty else { return nil }

        guard let selectedMediaSource else {
            return options.startIndex
        }

        if let selectedMediaSourceID = selectedMediaSource.id,
           let selectedIndex = options.firstIndex(where: { $0.sourceID == selectedMediaSourceID })
        {
            return selectedIndex
        }

        if let selectedMediaSourceETag = selectedMediaSource.eTag,
           let selectedIndex = options.firstIndex(where: { $0.sourceETag == selectedMediaSourceETag })
        {
            return selectedIndex
        }

        guard let selectedIndex = mediaSources.firstIndex(of: selectedMediaSource) else {
            return options.startIndex
        }

        return selectedIndex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            MediaSourceSelectorHeader(
                currentOptionNumber: options.isEmpty ? 0 : clampedFocusedIndex + 1,
                optionCount: options.count
            )

            Button(action: selectFocusedOption) {
                MediaSourceOptionsWindow(
                    options: visibleOptions,
                    selectedOptionID: selectedOptionID,
                    focusedIndex: clampedFocusedIndex,
                    rowHeight: Self.optionRowHeight
                )
            }
            .buttonStyle(MediaSourceWindowButtonStyle())
            .focused($isSelectorFocused)
            .focusEffectDisabled()
            .onMoveCommand(perform: moveFocus)
        }
        .padding(48)
        .frame(width: 1240, height: Self.selectorHeight)
        .focusSection()
        .defaultFocus($isSelectorFocused, true, priority: .userInitiated)
        .onAppear {
            focusedIndex = clampedFocusedIndex
            isSelectorFocused = true
        }
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            focusedIndex = max(clampedFocusedIndex - 1, 0)
        case .down:
            focusedIndex = min(clampedFocusedIndex + 1, max(options.count - 1, 0))
        default:
            break
        }
    }

    private func selectFocusedOption() {
        guard options.indices.contains(clampedFocusedIndex) else { return }

        onSelect(options[clampedFocusedIndex])
    }
}

private struct MediaSourceWindowButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

private struct MediaSourceSelectorHeader: View {

    let currentOptionNumber: Int
    let optionCount: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.version)
                .font(.headline.weight(.semibold))

            Spacer()

            Text("\(currentOptionNumber.formatted()) / \(optionCount.formatted())")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
                .monospacedDigit()
        }
    }
}

private struct MediaSourceOptionsWindow: View {

    let options: [ItemView.MediaSourceMenu.Option]
    let selectedOptionID: String?
    let focusedIndex: Int
    let rowHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(options) { option in
                MediaSourceRow(
                    option: option,
                    isSelected: option.id == selectedOptionID,
                    isFocused: option.index == focusedIndex
                )
                .equatable()
                .frame(height: rowHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct MediaSourceRow: View, Equatable {

    let option: ItemView.MediaSourceMenu.Option
    let isSelected: Bool
    let isFocused: Bool

    private var foregroundColor: Color {
        isFocused ? .black : .white
    }

    private var selectionColor: Color {
        isFocused ? .black : .white
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            MediaSourceSelectionIndicator(
                color: selectionColor,
                isSelected: isSelected
            )

            Text(option.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(foregroundColor)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isFocused ? Color.white : Color.white.opacity(isSelected ? 0.12 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(isSelected && !isFocused ? 0.14 : 0), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

private struct MediaSourceSelectionIndicator: View, Equatable {

    let color: Color
    let isSelected: Bool

    private var circleOpacity: Double {
        isSelected ? 0.62 : 0.36
    }

    private var fillOpacity: Double {
        isSelected ? 0.08 : 0
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(fillOpacity))

            Circle()
                .strokeBorder(color.opacity(circleOpacity), lineWidth: 2.25)

            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
                .opacity(isSelected ? 1 : 0)
        }
        .frame(width: 32, height: 32)
        .frame(width: 42)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}
