//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import SwiftUI

extension PlatformItemView {

    static func shouldPresentMediaSourceSelector(for viewModel: ItemViewModel) -> Bool {
        let loadedSourceCount = viewModel.playButtonItem?.mediaSources?.count ?? 0
        let advertisedSourceCount = viewModel.playButtonItem?.mediaSourceCount

        if loadedSourceCount > 1 || advertisedSourceCount.map({ $0 > 1 }) == true {
            return true
        }

        // A missing count does not establish that an online item has only one
        // version. Keep discovery available until the catalogue has been
        // requested once for this item.
        return advertisedSourceCount == nil
            && viewModel.versionSourcesItemID != viewModel.playButtonItem?.id
    }
}

private struct MediaSourceOption: Identifiable, Equatable {

    let id: String
    let source: MediaSourceInfo
    let title: String
    let searchText: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
    }

    static func makeOptions(from mediaSources: [MediaSourceInfo]) -> [Self] {
        var identityOccurrences: [String: Int] = [:]

        return mediaSources.map { source in
            let title = sanitizedTitle(for: source)
            let identity = identity(for: source, title: title)
            let occurrence = identityOccurrences[identity, default: 0]
            identityOccurrences[identity] = occurrence + 1

            return Self(
                id: "\(identity)#\(occurrence)",
                source: source,
                title: title,
                searchText: normalizedSearchText(title)
            )
        }
    }

    static func selectedID(
        for selectedSource: MediaSourceInfo?,
        in options: [Self]
    ) -> ID? {
        guard let selectedSource else { return options.first?.id }

        if let selectedETag = selectedSource.eTag?.nilIfBlank {
            let matchingOptions = options.filter { $0.source.eTag?.nilIfBlank == selectedETag }
            if matchingOptions.count == 1 {
                return matchingOptions[0].id
            }

            if let exactOption = matchingOptions.first(where: { $0.source == selectedSource }) {
                return exactOption.id
            }
        }

        if let selectedID = selectedSource.id?.nilIfBlank {
            let matchingOptions = options.filter { $0.source.id?.nilIfBlank == selectedID }
            if matchingOptions.count == 1 {
                return matchingOptions[0].id
            }

            if let exactOption = matchingOptions.first(where: { $0.source == selectedSource }) {
                return exactOption.id
            }
        }

        return options.first(where: { $0.source == selectedSource })?.id
            ?? options.first?.id
    }

    static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func identity(for source: MediaSourceInfo, title: String) -> String {
        if let eTag = source.eTag?.nilIfBlank {
            return "etag:\(eTag)"
        }

        if let id = source.id?.nilIfBlank {
            return "id:\(id)"
        }

        if let path = source.path?.nilIfBlank {
            return "path:\(path)"
        }

        return "title:\(title)"
    }

    private static func sanitizedTitle(for source: MediaSourceInfo) -> String {
        let lines = source.displayTitle
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(\.isNotEmpty)

        return lines.isEmpty ? source.displayTitle : lines.joined(separator: "\n")
    }
}

private struct MediaSourceSearchEntry {

    let id: MediaSourceOption.ID
    let searchText: String
}

struct MediaSourceSelector: View {

    @Environment(\.dismiss)
    private var dismiss

    @FocusState
    private var focusedOptionID: MediaSourceOption.ID?

    @State
    private var options: [MediaSourceOption] = []
    @State
    private var filteredOptions: [MediaSourceOption] = []
    @State
    private var isPreparingOptions = true
    @State
    private var searchQuery = ""
    @State
    private var searchTask: Task<Void, Never>?

    @ObservedObject
    var viewModel: ItemViewModel

    private var playbackItemID: String? {
        viewModel.playButtonItem?.id
    }

    private var isLoading: Bool {
        isPreparingOptions
            || viewModel.isLoadingPlaybackMediaSources
    }

    private var selectedOptionID: MediaSourceOption.ID? {
        MediaSourceOption.selectedID(
            for: viewModel.selectedMediaSource,
            in: options
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                Group {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredOptions.isEmpty {
                        ContentUnavailableView.search
                    } else {
                        optionList
                    }
                }
                .task(id: playbackItemID) {
                    await loadOptions(scrollProxy: scrollProxy)
                }
            }
            .toolbar {
                ToolbarItem(placement: cancellationToolbarPlacement) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.cancel)
                }

                ToolbarItem(placement: .principal) {
                    Text(navigationTitle)
                        .font(.headline)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .searchable(text: $searchQuery, prompt: L10n.search)
        .onChange(of: searchQuery) { newValue in
            filterOptions(for: newValue)
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var navigationTitle: String {
        guard !isLoading else { return L10n.version }

        #if os(tvOS)
        if let focusedOptionID,
           let focusedIndex = filteredOptions.firstIndex(where: { $0.id == focusedOptionID })
        {
            return "\(L10n.version) \((focusedIndex + 1).formatted()) / \(filteredOptions.count.formatted())"
        }
        #endif

        return "\(L10n.version) (\(options.count.formatted()))"
    }

    private var cancellationToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .cancellationAction
        #else
        .automatic
        #endif
    }

    private var optionList: some View {
        let selectedOptionID = selectedOptionID

        return List(filteredOptions) { option in
            Button {
                viewModel.send(.selectMediaSource(option.source))
                dismiss()
            } label: {
                MediaSourceOptionRow(
                    option: option,
                    item: viewModel.playButtonItem,
                    isSelected: option.id == selectedOptionID
                )
                .equatable()
            }
            .buttonStyle(.plain)
            .focused($focusedOptionID, equals: option.id)
            .id(option.id)
        }
        .listStyle(.plain)
    }

    @MainActor
    private func loadOptions(scrollProxy: ScrollViewProxy) async {
        isPreparingOptions = true
        defer { isPreparingOptions = false }

        await viewModel.waitForMediaSourceCatalogue()

        guard !Task.isCancelled else { return }

        let loadedOptions = MediaSourceOption.makeOptions(
            from: viewModel.playButtonItem?.mediaSources ?? []
        )
        options = loadedOptions
        applyFilter(searchQuery)

        await Task.yield()

        if let selectedID = MediaSourceOption.selectedID(
            for: viewModel.selectedMediaSource,
            in: loadedOptions
        ) {
            #if os(tvOS)
            focusedOptionID = selectedID
            #endif
            scrollProxy.scrollTo(selectedID, anchor: .center)
        }
    }

    private func filterOptions(for query: String) {
        searchTask?.cancel()

        let normalizedTerms = MediaSourceOption.normalizedSearchText(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let searchEntries = options.map { option in
            MediaSourceSearchEntry(id: option.id, searchText: option.searchText)
        }

        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            guard normalizedTerms.isNotEmpty else {
                filteredOptions = options
                return
            }

            let matchingIDs = await Task.detached(priority: .userInitiated) {
                Set(searchEntries.lazy.filter { entry in
                    normalizedTerms.allSatisfy { entry.searchText.contains($0) }
                }.map(\.id))
            }.value

            guard !Task.isCancelled, searchQuery == query else { return }
            filteredOptions = options.filter { matchingIDs.contains($0.id) }
            #if os(tvOS)
            focusedOptionID = filteredOptions.first(where: { $0.id == selectedOptionID })?.id
                ?? filteredOptions.first?.id
            #endif
        }
    }

    private func applyFilter(_ query: String) {
        let terms = MediaSourceOption.normalizedSearchText(query)
            .split(whereSeparator: \.isWhitespace)

        guard terms.isNotEmpty else {
            filteredOptions = options
            return
        }

        filteredOptions = options.filter { option in
            terms.allSatisfy { option.searchText.contains($0) }
        }
    }
}

private struct MediaSourceOptionRow: View, Equatable {

    @Environment(\.isFocused)
    private var isFocused

    #if os(iOS)
    @ObservedObject
    private var downloadManager = Container.shared.downloadManager()
    #endif

    let option: MediaSourceOption
    let item: BaseItemDto?
    let isSelected: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.option == rhs.option
            && lhs.item?.id == rhs.item?.id
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)

            Text(option.title)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let downloadSystemImage {
                Image(systemName: downloadSystemImage)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        #if os(tvOS)
            .padding(.horizontal, 18)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(isFocused ? 0.18 : isSelected ? 0.1 : 0))
            }
        #endif
            .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var downloadSystemImage: String? {
        #if os(iOS)
        guard let item,
              let task = downloadManager.task(for: item, mediaSource: option.source)
        else { return nil }

        switch task.state {
        case .complete:
            return "arrow.down.circle.fill"
        case .downloading, .resolving:
            return "arrow.down.circle"
        case .paused:
            return "pause.circle"
        case .cancelled, .error:
            return "exclamationmark.triangle"
        case .ready:
            return nil
        }
        #else
        nil
        #endif
    }
}
