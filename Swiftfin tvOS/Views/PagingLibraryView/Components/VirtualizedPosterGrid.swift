//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import Nuke
import SwiftUI
import UIKit

extension PagingLibraryView {

    struct VirtualizedPosterGrid: UIViewRepresentable {

        let items: [Element]
        let posterType: PosterDisplayType
        let displayType: LibraryDisplayType
        let columnCount: Int
        let spacing: CGFloat
        let pagingPrefetchRows: Int
        let onSelect: (Element) -> Void
        let onNearEnd: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        func makeUIView(context: Context) -> UICollectionView {
            let layout = UICollectionViewFlowLayout()
            layout.minimumInteritemSpacing = spacing
            layout.minimumLineSpacing = spacing
            layout.scrollDirection = .vertical

            let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
            collectionView.allowsSelection = true
            collectionView.backgroundColor = .clear
            collectionView.contentInset = UIEdgeInsets(
                top: spacing,
                left: spacing,
                bottom: spacing,
                right: spacing
            )
            collectionView.delegate = context.coordinator
            collectionView.prefetchDataSource = context.coordinator
            collectionView.remembersLastFocusedIndexPath = true
            collectionView.showsVerticalScrollIndicator = false

            context.coordinator.configureDataSource(for: collectionView)
            context.coordinator.update(parent: self, in: collectionView)

            return collectionView
        }

        func updateUIView(_ collectionView: UICollectionView, context: Context) {
            context.coordinator.update(parent: self, in: collectionView)
        }
    }
}

extension PagingLibraryView.VirtualizedPosterGrid {

    final class Coordinator: NSObject, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {

        private enum Section {
            case main
        }

        private var dataSource: UICollectionViewDiffableDataSource<Section, Element.ID>?
        private let imagePrefetcher = ImagePrefetcher(
            pipeline: ImagePipeline.Swiftfin.posters,
            destination: .memoryCache,
            maxConcurrentRequestCount: 2
        )
        private var itemLookup: [Element.ID: Element] = [:]
        private var lastItemIDs: [Element.ID] = []
        private var lastLayoutState: LayoutState?
        private var lastNearEndItemCount = 0
        private var isNearEndCallbackScheduled = false
        private var parent: PagingLibraryView.VirtualizedPosterGrid
        private var preheatedImageURLs: Set<URL> = []

        private let preheatedItemWindowCount = 36
        private let gridLandscapeMaxWidth: CGFloat = 300
        private let gridPortraitMaxWidth: CGFloat = 200
        private let listLandscapeMaxWidth: CGFloat = 110
        private let listPortraitMaxWidth: CGFloat = 60

        private struct LayoutState: Equatable {
            let width: CGFloat
            let posterType: PosterDisplayType
            let displayType: LibraryDisplayType
            let columnCount: Int
            let spacing: CGFloat
        }

        init(parent: PagingLibraryView.VirtualizedPosterGrid) {
            self.parent = parent
        }

        func configureDataSource(for collectionView: UICollectionView) {
            let cellRegistration = UICollectionView
                .CellRegistration<FocusableHostingCollectionViewCell, Element.ID> { [weak self] cell, _, id in
                    guard let self, let item = itemLookup[id] else {
                        cell.contentConfiguration = nil
                        return
                    }

                    cell.backgroundColor = .clear
                    cell.clipsToBounds = false
                    cell.contentView.clipsToBounds = false
                    cell.applyFocusAppearance(isFocused: cell.isFocused, animated: false)
                    self.configure(
                        cell,
                        with: item,
                        focusState: cell.focusState
                    )
                }

            dataSource = UICollectionViewDiffableDataSource<
                Section,
                Element.ID
            >(collectionView: collectionView) { collectionView, indexPath, id in
                collectionView.dequeueConfiguredReusableCell(
                    using: cellRegistration,
                    for: indexPath,
                    item: id
                )
            }
        }

        func update(parent: PagingLibraryView.VirtualizedPosterGrid, in collectionView: UICollectionView) {
            if parent.items.count < lastNearEndItemCount {
                lastNearEndItemCount = 0
            }

            self.parent = parent

            let itemIDs = parent.items.map(\.id)
            if itemIDs != lastItemIDs {
                itemLookup = Dictionary(uniqueKeysWithValues: parent.items.map { ($0.id, $0) })
                applySnapshot(itemIDs: itemIDs)
                lastItemIDs = itemIDs
                updatePreheatedImages(in: collectionView)
            }

            let layoutState = LayoutState(
                width: collectionView.bounds.width,
                posterType: parent.posterType,
                displayType: parent.displayType,
                columnCount: parent.columnCount,
                spacing: parent.spacing
            )

            if layoutState != lastLayoutState {
                updateLayout(in: collectionView)
                lastLayoutState = layoutState
            }
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard let item = item(at: indexPath) else { return }
            parent.onSelect(item)
        }

        func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
            true
        }

        func collectionView(
            _ collectionView: UICollectionView,
            willDisplay cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            loadNextPageIfNeeded(for: indexPath.item)
            updatePreheatedImages(in: collectionView)
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            guard let maxIndex = indexPaths.map(\.item).max() else { return }
            loadNextPageIfNeeded(for: maxIndex)
            updatePreheatedImages(in: collectionView, around: maxIndex)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            updatePreheatedImages(in: collectionView)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            itemSize(for: collectionView.bounds.width)
        }

        private func applySnapshot(itemIDs: [Element.ID]) {
            guard let dataSource else { return }

            if lastItemIDs.isEmpty || itemIDs.count < lastItemIDs.count || !itemIDs.starts(with: lastItemIDs) {
                var snapshot = NSDiffableDataSourceSnapshot<Section, Element.ID>()
                snapshot.appendSections([.main])
                snapshot.appendItems(itemIDs, toSection: .main)
                dataSource.apply(snapshot, animatingDifferences: false)
                return
            }

            var snapshot = dataSource.snapshot()
            let newItemIDs = itemIDs.dropFirst(lastItemIDs.count)
            snapshot.appendItems(Array(newItemIDs), toSection: .main)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        private func updateLayout(in collectionView: UICollectionView) {
            guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }

            layout.minimumInteritemSpacing = parent.spacing
            layout.minimumLineSpacing = parent.spacing
            layout.itemSize = itemSize(for: collectionView.bounds.width)
            layout.invalidateLayout()
        }

        private func item(at indexPath: IndexPath) -> Element? {
            guard let id = dataSource?.itemIdentifier(for: indexPath) else { return nil }
            return itemLookup[id]
        }

        private func configure(
            _ cell: UICollectionViewCell,
            with item: Element,
            focusState: VirtualizedCellFocusState
        ) {
            cell.contentConfiguration = UIHostingConfiguration {
                self.cellContent(
                    for: item,
                    focusState: focusState
                )
            }
            .margins(.all, 0)
        }

        private func loadNextPageIfNeeded(for index: Int) {
            let itemCount = parent.items.count
            let nextPageThreshold = max(itemCount - parent.columnCount * parent.pagingPrefetchRows, 0)

            guard index >= nextPageThreshold else { return }
            guard itemCount > lastNearEndItemCount else { return }
            guard !isNearEndCallbackScheduled else { return }

            lastNearEndItemCount = itemCount
            isNearEndCallbackScheduled = true

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isNearEndCallbackScheduled = false
                self.parent.onNearEnd()
            }
        }

        private func updatePreheatedImages(in collectionView: UICollectionView, around preferredIndex: Int? = nil) {
            guard parent.items.isNotEmpty else {
                stopPreheatingImages()
                return
            }

            let visibleIndices = collectionView.indexPathsForVisibleItems.map(\.item)
            let centerIndex: Int = if let preferredIndex {
                preferredIndex
            } else if let minIndex = visibleIndices.min(), let maxIndex = visibleIndices.max() {
                (minIndex + maxIndex) / 2
            } else {
                0
            }

            let halfWindow = preheatedItemWindowCount / 2
            var lowerBound = max(centerIndex - halfWindow, 0)
            let upperBound = min(lowerBound + preheatedItemWindowCount, parent.items.count)
            lowerBound = max(upperBound - preheatedItemWindowCount, 0)

            let urls = Set(parent.items[lowerBound ..< upperBound].compactMap { preheatedImageURL(for: $0) })
            guard urls != preheatedImageURLs else { return }

            let urlsToStop = preheatedImageURLs.subtracting(urls)
            let urlsToStart = urls.subtracting(preheatedImageURLs)

            imagePrefetcher.stopPrefetching(with: Array(urlsToStop))
            imagePrefetcher.startPrefetching(with: Array(urlsToStart))
            preheatedImageURLs = urls
        }

        private func stopPreheatingImages() {
            guard preheatedImageURLs.isNotEmpty else { return }

            imagePrefetcher.stopPrefetching()
            preheatedImageURLs.removeAll()
        }

        private func preheatedImageURL(for item: Element) -> URL? {
            let imageSources: [ImageSource] = switch parent.displayType {
            case .grid:
                switch parent.posterType {
                case .landscape:
                    item.landscapeImageSources(maxWidth: gridLandscapeMaxWidth, quality: 90)
                case .portrait:
                    item.portraitImageSources(maxWidth: gridPortraitMaxWidth, quality: 90)
                case .square:
                    item.squareImageSources(maxWidth: gridPortraitMaxWidth, quality: 90)
                }
            case .list:
                switch parent.posterType {
                case .landscape:
                    item.landscapeImageSources(maxWidth: listLandscapeMaxWidth, quality: 90)
                case .portrait:
                    item.portraitImageSources(maxWidth: listPortraitMaxWidth, quality: 90)
                case .square:
                    item.squareImageSources(maxWidth: listPortraitMaxWidth, quality: 90)
                }
            }

            return imageSources.first?.url
        }

        private func itemSize(for collectionWidth: CGFloat) -> CGSize {
            let availableWidth = max(collectionWidth - parent.spacing * 2, 0)
            let totalInteritemSpacing = parent.spacing * CGFloat(max(parent.columnCount - 1, 0))
            let itemWidth = max((availableWidth - totalInteritemSpacing) / CGFloat(parent.columnCount), 1)

            switch parent.displayType {
            case .grid:
                return CGSize(
                    width: itemWidth,
                    height: itemWidth / parent.posterType.aspectRatio
                )
            case .list:
                return CGSize(
                    width: itemWidth,
                    height: parent.posterType.listRowHeight
                )
            }
        }

        @ViewBuilder
        private func cellContent(for item: Element, focusState: VirtualizedCellFocusState) -> some View {
            switch parent.displayType {
            case .grid:
                VirtualizedPosterCellContent(
                    item: item,
                    type: parent.posterType,
                    focusState: focusState
                )
            case .list:
                VirtualizedLibraryRowContent(
                    item: item,
                    posterType: parent.posterType,
                    focusState: focusState
                )
            }
        }
    }
}

private final class VirtualizedCellFocusState: ObservableObject {
    @Published
    var isFocused = false
}

private struct VirtualizedPosterCellContent<Item: Poster>: View {

    @EnvironmentTypeValue<Item>(\.posterOverlayRegistry)
    private var posterOverlayRegistry

    let item: Item
    let type: PosterDisplayType

    @ObservedObject
    var focusState: VirtualizedCellFocusState

    var body: some View {
        let overlay = posterOverlayRegistry?(item) ??
            PosterButton<Item>.DefaultOverlay(item: item)
            .eraseToAnyView()

        PosterImage(
            item: item,
            type: type,
            prefersBlurHashPlaceholder: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            overlay
                .posterOverlayFocus(focusState.isFocused)
        }
        .posterStyle(type)
        .virtualizedCellFocusEffect(focusState.isFocused)
        .accessibilityLabel(item.displayTitle)
        .matchedContextMenu(for: item)
    }
}

private struct VirtualizedLibraryRowContent<Item: Poster>: View {

    private let landscapeMaxWidth: CGFloat = 110
    private let portraitMaxWidth: CGFloat = 60

    let item: Item
    let posterType: PosterDisplayType

    @ObservedObject
    var focusState: VirtualizedCellFocusState

    private func imageSources(from item: Item) -> [ImageSource] {
        switch posterType {
        case .landscape:
            item.landscapeImageSources(maxWidth: landscapeMaxWidth, quality: 90)
        case .portrait:
            item.portraitImageSources(maxWidth: portraitMaxWidth, quality: 90)
        case .square:
            item.squareImageSources(maxWidth: portraitMaxWidth, quality: 90)
        }
    }

    @ViewBuilder
    private func itemAccessoryView(item: BaseItemDto) -> some View {
        DotHStack {
            if item.type == .episode, let seasonEpisodeLocator = item.seasonEpisodeLabel {
                Text(seasonEpisodeLocator)
            } else if let premiereYear = item.premiereDateYear {
                Text(premiereYear)
            }

            if let runtime = item.runTimeLabel {
                Text(runtime)
            }

            if let officialRating = item.officialRating {
                Text(officialRating)
            }
        }
    }

    @ViewBuilder
    private func personAccessoryView(person: BaseItemPerson) -> some View {
        if let subtitle = person.subtitle {
            Text(subtitle)
        }
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch item {
        case let item as BaseItemDto:
            itemAccessoryView(item: item)
        case let person as BaseItemPerson:
            personAccessoryView(person: person)
        default:
            AssertionFailureView("Used an unexpected type within a `PagingLibaryView`?")
        }
    }

    private var rowLeadingWidth: CGFloat {
        posterType == .landscape ? landscapeMaxWidth : portraitMaxWidth
    }

    var body: some View {
        HStack(alignment: .center, spacing: EdgeInsets.edgePadding) {
            ZStack {
                Color.clear

                ImageView(imageSources(from: item))
                    .failure {
                        SystemImageContentView(systemName: item.systemImage)
                    }
            }
            .posterStyle(posterType)
            .frame(width: rowLeadingWidth)
            .posterShadow()
            .padding(.vertical, 8)

            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.displayTitle)
                        .font(posterType == .landscape ? .subheadline : .callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    accessoryView
                        .font(.caption)
                        .foregroundColor(Color(UIColor.lightGray))
                }

                Spacer()
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, EdgeInsets.edgePadding)
        .foregroundStyle(.primary, .secondary)
        .virtualizedCellFocusEffect(focusState.isFocused)
        .accessibilityLabel(item.displayTitle)
    }
}

private final class FocusableHostingCollectionViewCell: UICollectionViewCell {

    let focusState = VirtualizedCellFocusState()

    override var canBecomeFocused: Bool {
        true
    }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)

        let nextView = context.nextFocusedView
        let isCellFocused = nextView == self || nextView?.isDescendant(of: self) == true

        coordinator.addCoordinatedAnimations {
            self.focusState.isFocused = isCellFocused
            self.applyFocusAppearance(isFocused: isCellFocused, animated: true)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        focusState.isFocused = false
        applyFocusAppearance(isFocused: false, animated: false)
        contentConfiguration = nil
    }

    func applyFocusAppearance(isFocused: Bool, animated: Bool) {
        let changes = {
            self.transform = isFocused ? CGAffineTransform(scaleX: 1.06, y: 1.06) : .identity
            self.layer.zPosition = isFocused ? 1 : 0
            self.layer.shadowColor = UIColor.black.cgColor
            self.layer.shadowOpacity = isFocused ? 0.45 : 0.22
            self.layer.shadowRadius = isFocused ? 24 : 4
            self.layer.shadowOffset = CGSize(width: 0, height: isFocused ? 14 : 2)
        }

        if animated {
            changes()
        } else {
            UIView.performWithoutAnimation(changes)
        }
    }
}

private extension View {

    @ViewBuilder
    func virtualizedCellFocusEffect(_ isFocused: Bool) -> some View {
        let cornerRadius: CGFloat = 18

        if #available(tvOS 26.0, *) {
            Group {
                if isFocused {
                    clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .glassEffect(
                            .regular.interactive(),
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        )
                } else {
                    clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
        } else {
            clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(isFocused ? 0.24 : 0.12), lineWidth: 1)
                }
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }
    }
}

private extension PosterDisplayType {

    var aspectRatio: CGFloat {
        switch self {
        case .landscape:
            1.77
        case .portrait:
            2 / 3
        case .square:
            1
        }
    }

    var listRowHeight: CGFloat {
        switch self {
        case .landscape:
            96
        case .portrait, .square:
            122
        }
    }
}
