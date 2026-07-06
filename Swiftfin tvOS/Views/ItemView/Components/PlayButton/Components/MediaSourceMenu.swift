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
            let title: String
        }

        @State
        private var isSelectorPresented = false

        @ObservedObject
        var viewModel: ItemViewModel

        private let mediaSources: [MediaSourceInfo]
        private let options: [Option]

        init(viewModel: ItemViewModel, mediaSources: [MediaSourceInfo]) {
            self.viewModel = viewModel
            self.mediaSources = mediaSources
            self.options = mediaSources.enumerated().map { index, mediaSource in
                let titleLines = mediaSource.displayTitle
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter(\.isNotEmpty)
                let id = mediaSource.id ?? "\(index)-\(mediaSource.displayTitle)"

                return Option(
                    id: id,
                    index: index,
                    sourceID: mediaSource.id,
                    title: titleLines.isEmpty ? mediaSource.displayTitle : titleLines.joined(separator: "\n")
                )
            }
        }

        // MARK: - Selected Media Source

        private var selectedOptionID: String? {
            guard let selectedMediaSource = viewModel.selectedMediaSource else {
                return options.first?.id
            }

            if let selectedMediaSourceID = selectedMediaSource.id,
               let selectedOption = options.first(where: { $0.sourceID == selectedMediaSourceID })
            {
                return selectedOption.id
            }

            guard let selectedIndex = mediaSources.firstIndex(of: selectedMediaSource) else {
                return options.first?.id
            }

            return options[selectedIndex].id
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
                    options: options,
                    selectedOptionID: selectedOptionID
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
    private var focusedOptionID: String?

    let options: [ItemView.MediaSourceMenu.Option]
    let selectedOptionID: String?
    let onSelect: (ItemView.MediaSourceMenu.Option) -> Void

    private var defaultFocusedOptionID: String? {
        selectedOptionID ?? options.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.version)
                        .font(.headline.weight(.semibold))

                    Spacer()

                    Text("\(options.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .monospacedDigit()
                }

                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(options) { option in
                            Button {
                                onSelect(option)
                            } label: {
                                MediaSourceRow(
                                    option: option,
                                    isSelected: option.id == selectedOptionID,
                                    isFocused: option.id == focusedOptionID
                                )
                                .equatable()
                            }
                            .buttonStyle(.borderless)
                            .id(option.id)
                            .focused($focusedOptionID, equals: option.id)
                            .focusEffectDisabled()
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 32)
                }
            }
            .padding(48)
            .frame(width: 1240, height: 780)
            .focusSection()
            .defaultFocus(
                $focusedOptionID,
                defaultFocusedOptionID,
                priority: .userInitiated
            )
            .onAppear {
                focusedOptionID = defaultFocusedOptionID

                if let defaultFocusedOptionID {
                    proxy.scrollTo(defaultFocusedOptionID, anchor: .center)
                }
            }
        }
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
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(selectionColor)
                .opacity(isSelected ? 1 : 0)
                .frame(width: 16, height: 22)
                .padding(.top, 2)

            Text(option.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(foregroundColor)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 22)
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
