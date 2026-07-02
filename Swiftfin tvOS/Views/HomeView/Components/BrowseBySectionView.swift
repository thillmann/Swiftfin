//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftUI

extension HomeView {

    struct BrowseBySectionView: View {

        private enum FocusedElement: Hashable {
            case option(String)
            case browseAllGuide
            case browseAll
        }

        @Router
        private var router

        @FocusState
        private var focusedElement: FocusedElement?

        @StateObject
        private var viewModel: BrowseBySectionViewModel

        @State
        private var selectedOption: BrowseByOption

        @State
        private var pendingRequestItem: SeerrClient.MediaResult?

        @State
        private var contentSize: CGSize = .zero

        @State
        private var lastFocusedElement: FocusedElement?

        let group: BrowseByGroup
        let onPrepareForNavigation: () -> Void

        private let horizontalPadding: CGFloat = EdgeInsets.edgePadding
        private let logoSpacing: CGFloat = 12
        private let posterSpacing: CGFloat = 30
        private let heroCopyWidth: CGFloat = 430
        private let heroContentSpacing: CGFloat = 56
        private let heroLogoStageSize = CGSize(width: 360, height: 140)
        private let heroTaglineHeight: CGFloat = 30
        private let containerHorizontalPadding: CGFloat = 40
        private let containerVerticalPadding: CGFloat = 36
        private let containerCornerRadius: CGFloat = 20
        private let railToHeroSpacing: CGFloat = 34
        private let railButtonWidth: CGFloat = 154
        private let railButtonHeight: CGFloat = FeatureButtonTokens.baseHeight
        private let railLogoStageSize = CGSize(width: 148, height: 58)

        private var availableWidth: CGFloat {
            contentSize.width > 0 ? contentSize.width : UIScreen.main.bounds.width
        }

        private var containerWidth: CGFloat {
            max(availableWidth - horizontalPadding * 2, 1)
        }

        private var posterWidth: CGFloat {
            let standardPosterSpacing = EdgeInsets.edgePadding - 40
            let standardPosterWidth = (availableWidth - horizontalPadding * 2 - standardPosterSpacing * 5) / 6
            let containerAvailableWidth = containerWidth - containerHorizontalPadding * 2
            let widthConstrainedValue = (
                containerAvailableWidth - heroCopyWidth - heroContentSpacing - posterSpacing * 3
            ) / 4

            return max(min(widthConstrainedValue, standardPosterWidth), 150)
        }

        private var posterHeight: CGFloat {
            posterWidth / (2 / 3)
        }

        private var posterStripWidth: CGFloat {
            posterWidth * 4 + posterSpacing * 3
        }

        private var options: [BrowseByOption] {
            group.options
        }

        init(
            group: BrowseByGroup,
            onPrepareForNavigation: @escaping () -> Void
        ) {
            self.group = group
            self.onPrepareForNavigation = onPrepareForNavigation

            let selectedOption = group.initialOption
            self._selectedOption = State(initialValue: selectedOption)
            self._viewModel = StateObject(wrappedValue: BrowseBySectionViewModel(selectedOption: selectedOption))
        }

        var body: some View {
            if SeerrIntegration.isAvailable, options.isNotEmpty {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    optionContainer
                }
                .trackingSize($contentSize)
                .focusSection()
                .onFirstAppear {
                    selectOption(selectedOption)
                }
                .onChange(of: selectedOption) { _, option in
                    selectOption(option)
                }
                .onChange(of: focusedElement) { _, element in
                    redirectFocusGuide(element)
                }
                .fullScreenCover(item: $pendingRequestItem) { item in
                    SeerrRequestView(item: item) {
                        viewModel.markRequested(item)
                    }
                }
            }
        }

        private var optionContainer: some View {
            VStack(alignment: .leading, spacing: 0) {
                optionRail
                railToBrowseAllFocusGuide
                hero
            }
            .padding(.horizontal, containerHorizontalPadding)
            .padding(.vertical, containerVerticalPadding)
            .frame(width: containerWidth, alignment: .leading)
            .background {
                optionContainerBackground
            }
            .overlay {
                RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous))
            .padding(.horizontal, horizontalPadding)
        }

        @ViewBuilder
        private var optionContainerBackground: some View {
            let shape = RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous)

            ZStack {
                if #available(tvOS 26.0, *) {
                    shape
                        .fill(.clear)
                        .glassEffect(
                            .regular.tint(selectedOption.theme.backgroundColor.opacity(0.34)),
                            in: shape
                        )
                } else {
                    shape
                        .fill(.ultraThinMaterial)
                }

                BrowseByThemeBackground(option: selectedOption)
                    .opacity(0.72)

                shape
                    .fill(.black.opacity(0.08))
            }
        }

        private var header: some View {
            HStack {
                Text(group.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .accessibility(addTraits: [.isHeader])

                Spacer()
            }
            .padding(.horizontal, horizontalPadding)
        }

        private var optionRail: some View {
            ScrollView(.horizontal) {
                LazyHStack(spacing: logoSpacing) {
                    ForEach(options) { option in
                        optionButton(option)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }

        private var railToBrowseAllFocusGuide: some View {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: railToHeroSpacing)
                .focusable()
                .focused($focusedElement, equals: .browseAllGuide)
                .accessibilityHidden(true)
        }

        private var hero: some View {
            HStack(alignment: .top, spacing: heroContentSpacing) {
                heroCopy
                    .frame(width: heroCopyWidth, alignment: .leading)

                Spacer(minLength: 0)

                posterStrip
            }
        }

        private var heroCopy: some View {
            VStack(alignment: .center, spacing: 22) {
                heroLogo

                Text(selectedOption.tagline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .frame(maxWidth: .infinity)
                    .frame(height: heroTaglineHeight, alignment: .center)

                Button {
                    onPrepareForNavigation()
                    router.route(to: .browseBy(selectedOption))
                } label: {
                    Text(L10n.browseAll)
                        .font(FeatureButtonTokens.labelFont)
                        .padding(.horizontal, 42)
                        .frame(maxHeight: .infinity)
                }
                .buttonStyle(.featureButton)
                .frame(height: FeatureButtonTokens.baseHeight)
                .frame(maxWidth: .infinity, alignment: .center)
                .focused($focusedElement, equals: .browseAll)
            }
            .frame(height: posterHeight, alignment: .center)
        }

        private var heroLogo: some View {
            BrowseByLogoView(
                option: selectedOption,
                variant: .hero,
                alignment: .center,
                foregroundColor: .white
            )
            .frame(
                width: selectedOption.heroLogo.frameSize.width,
                height: selectedOption.heroLogo.frameSize.height,
                alignment: .center
            )
            .frame(
                width: heroLogoStageSize.width,
                height: heroLogoStageSize.height,
                alignment: .center
            )
        }

        @ViewBuilder
        private var posterStrip: some View {
            if viewModel.isLoading, viewModel.items.isEmpty {
                ProgressView()
                    .frame(width: posterStripWidth, height: posterHeight)
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(L10n.noItems, systemImage: "film")
                    .frame(width: posterStripWidth, height: posterHeight)
            } else {
                HStack(spacing: posterSpacing) {
                    ForEach(viewModel.items.prefix(4)) { item in
                        PosterButton(
                            item: item,
                            type: .portrait,
                            usesContextMenu: false
                        ) {
                            select(item)
                        } overlay: {
                            UnifiedMediaResultPosterOverlay(item: item)
                        }
                        .frame(width: posterWidth, height: posterHeight)
                    }
                }
                .frame(width: posterStripWidth, height: posterHeight)
            }
        }

        private func optionButton(_ option: BrowseByOption) -> some View {
            let isSelected = option == selectedOption

            return Button {
                selectedOption = option
            } label: {
                BrowseByRailLogoView(
                    option: option,
                    isSelected: isSelected,
                    stageSize: railLogoStageSize
                )
            }
            .buttonStyle(
                BrowseByButtonStyle(
                    isSelected: isSelected,
                    width: railButtonWidth,
                    height: railButtonHeight
                )
            )
            .accessibilityLabel(option.name)
            .focusEffectDisabled()
            .focused($focusedElement, equals: .option(option.id))
        }

        private func select(_ item: UnifiedMediaResult) {
            onPrepareForNavigation()

            switch item {
            case let .jellyfin(baseItem):
                router.route(to: .item(item: baseItem))
            case let .seerr(seerrItem):
                pendingRequestItem = seerrItem
            }
        }

        private func selectOption(_ option: BrowseByOption) {
            Task {
                await viewModel.select(option)
            }
        }

        private func redirectFocusGuide(_ element: FocusedElement?) {
            guard element == .browseAllGuide else {
                lastFocusedElement = element
                return
            }

            switch lastFocusedElement {
            case .option(_)?:
                focusedElement = .browseAll
            default:
                focusedElement = .option(selectedOption.id)
            }
        }
    }
}

extension HomeView.BrowseBySectionView {

    @MainActor
    final class BrowseBySectionViewModel: ViewModel, SeerrRequestStateUpdating {

        @Published
        private(set) var items: [UnifiedMediaResult] = []

        @Published
        private(set) var isLoading = false

        private var cachedItems: [String: [UnifiedMediaResult]] = [:]
        private var cachedRawItems: [String: [SeerrClient.MediaResult]] = [:]
        private var loadingOptionIDs = Set<String>()
        private var selectedOption: BrowseByOption

        private let resultLimit = 12
        private let releaseDateParser: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        init(selectedOption: BrowseByOption) {
            self.selectedOption = selectedOption
        }

        func select(_ option: BrowseByOption) async {
            selectedOption = option
            items = cachedItems[option.id] ?? []
            isLoading = loadingOptionIDs.contains(option.id)

            if cachedItems[option.id] == nil {
                await load(option)
            }
        }

        func markRequested(_ requestedItem: SeerrClient.MediaResult) {
            cachedRawItems = cachedRawItems.mapValues { items in
                SeerrLibraryMatcher.updatingRequestStatus(
                    in: items,
                    for: requestedItem,
                    to: .pending
                )
            }

            Task {
                await updateItems(for: selectedOption)
            }
        }

        private func load(_ option: BrowseByOption) async {
            guard !loadingOptionIDs.contains(option.id) else { return }

            loadingOptionIDs.insert(option.id)
            if selectedOption == option {
                isLoading = true
            }
            defer {
                loadingOptionIDs.remove(option.id)
                if selectedOption == option {
                    isLoading = false
                }
            }

            let rawItems = await fetchItems(for: option)

            cachedRawItems[option.id] = rawItems
            await updateItems(for: option)
        }

        private func fetchItems(for option: BrowseByOption) async -> [SeerrClient.MediaResult] {
            let firstPageResult = await option.kind.discover(
                optionID: option.seerrID,
                page: 1,
                language: "en"
            )

            guard case let .success(firstPage) = firstPageResult else { return [] }

            var results: [SeerrClient.MediaResult] = []
            var seenIDs = Set<String>()
            appendFiltered(firstPage.results, for: option, to: &results, seenIDs: &seenIDs)
            let totalPages = firstPage.totalPages ?? 1

            guard totalPages > 1, results.count < resultLimit else {
                return results
            }

            for page in 2 ... totalPages {
                let pageResult = await option.kind.discover(
                    optionID: option.seerrID,
                    page: page,
                    language: "en"
                )

                guard case let .success(response) = pageResult else { break }
                appendFiltered(response.results, for: option, to: &results, seenIDs: &seenIDs)

                if results.count >= resultLimit {
                    break
                }
            }

            return results
        }

        private func appendFiltered(
            _ pageResults: [SeerrClient.MediaResult],
            for option: BrowseByOption,
            to results: inout [SeerrClient.MediaResult],
            seenIDs: inout Set<String>
        ) {
            let remainingCount = resultLimit - results.count
            guard remainingCount > 0 else { return }

            let newItems = pageResults
                .filter { isReleasedEnglishItem($0, for: option) }
                .filter { seenIDs.insert(SeerrLibraryMatcher.key(for: $0)).inserted }
                .prefix(remainingCount)

            results.append(contentsOf: newItems)
        }

        private func isReleasedEnglishItem(_ item: SeerrClient.MediaResult, for option: BrowseByOption) -> Bool {
            guard item.mediaType == option.kind.mediaType, item.originalLanguage == "en" else { return false }
            guard let value = item.releaseDate ?? item.firstAirDate,
                  let releaseDate = releaseDateParser.date(from: value)
            else {
                return false
            }

            return releaseDate <= Date()
        }

        private func updateItems(for option: BrowseByOption) async {
            guard let rawItems = cachedRawItems[option.id] else { return }

            let unifiedItems = await SeerrLibraryMatcher.unifiedResults(for: rawItems, using: self)
            cachedItems[option.id] = unifiedItems

            if selectedOption == option {
                items = unifiedItems
            }
        }
    }
}

private struct BrowseByRailLogoView: View {

    let option: BrowseByOption
    let isSelected: Bool
    let stageSize: CGSize

    var body: some View {
        BrowseByLogoView(
            option: option,
            variant: .rail,
            foregroundColor: foregroundColor
        )
        .frame(width: option.railLogo.frameSize.width, height: option.railLogo.frameSize.height)
        .offset(option.railLogo.offset)
        .opacity(isSelected ? 1 : 0.76)
        .frame(width: stageSize.width, height: stageSize.height)
    }

    private var foregroundColor: Color {
        isSelected ? .black : .white
    }
}

private struct BrowseByButtonStyle: ButtonStyle {

    @Environment(\.isFocused)
    var isFocused: Bool
    let isSelected: Bool
    var width: CGFloat?
    var height: CGFloat = FeatureButtonTokens.baseHeight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(isFocused ? .black : .white.opacity(isSelected ? 1 : 0.72))
            .frame(width: width, height: height)
            .background {
                Capsule(style: .continuous)
                    .fill(.white.opacity(isSelected ? 1 : isFocused ? 0.2 : 0))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(!isSelected && isFocused ? 0.16 : 0), lineWidth: 1)
                    }
            }
            .scaleEffect(isFocused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
