//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

struct PlatformItemView: View {

    static let detailSectionSpacing: CGFloat = 24

    protocol ScrollContainerView: View {

        associatedtype Content: View

        init(viewModel: ItemViewModel, content: @escaping () -> Content)
    }

    @Default(.Customization.platformItemViewType)
    private var itemViewType

    @Router
    private var router

    @StateObject
    private var viewModel: ItemViewModel

    private static func typeViewModel(for item: BaseItemDto) -> ItemViewModel {
        switch item.type {
        case .boxSet, .person, .musicArtist:
            return CollectionItemViewModel(item: item)
        case .episode:
            return EpisodeItemViewModel(item: item)
        case .movie:
            return MovieItemViewModel(item: item)
        case .musicVideo, .video:
            return ItemViewModel(item: item)
        case .series:
            return SeriesItemViewModel(item: item)
        default:
            assertionFailure("Unsupported item")
            return ItemViewModel(item: item)
        }
    }

    private static func typeViewModel(for record: DownloadRecord) -> ItemViewModel {
        switch record.item.type {
        case .episode:
            return EpisodeItemViewModel(item: record.item, offlineRecord: record)
        case .movie:
            return MovieItemViewModel(item: record.item, offlineRecord: record)
        default:
            assertionFailure("Unsupported downloaded item")
            return ItemViewModel(item: record.item, offlineRecord: record)
        }
    }

    init(item: BaseItemDto) {
        self._viewModel = StateObject(wrappedValue: Self.typeViewModel(for: item))
    }

    init(downloadRecord: DownloadRecord) {
        self._viewModel = StateObject(wrappedValue: Self.typeViewModel(for: downloadRecord))
    }

    @ViewBuilder
    private var scrollContentView: some View {
        VStack(alignment: .leading, spacing: Self.detailSectionSpacing) {
            switch viewModel.item.type {
            case .boxSet, .person, .musicArtist:
                CollectionItemContentView(viewModel: viewModel as! CollectionItemViewModel)
            case .episode, .musicVideo, .video:
                SimpleItemContentView(viewModel: viewModel)
            case .movie:
                MovieItemContentView(viewModel: viewModel as! MovieItemViewModel)
            case .series:
                SeriesItemContentView(viewModel: viewModel as! SeriesItemViewModel)
            default:
                Text(L10n.notImplementedYetWithType(viewModel.item.type ?? "--"))
            }

            if !viewModel.isOffline,
               [.episode, .movie, .series].contains(viewModel.item.type)
            {
                ItemManagementButtons(item: viewModel.item)
            }
        }
    }

    // TODO: break out into pad vs phone views based on item type
    private func scrollContainerView(
        viewModel: ItemViewModel,
        content: @escaping () -> some View
    ) -> any ScrollContainerView {

        if viewModel.item.type == .person {
            return PlainScrollView(viewModel: viewModel, content: content)
        }

        if UIDevice.isPad {
            return iPadOSCinematicScrollView(viewModel: viewModel, content: content)
        }

        switch viewModel.item.type {
        case .movie, .series:
            switch itemViewType {
            case .compactPoster:
                return CompactPosterScrollView(viewModel: viewModel, content: content)
            case .compactLogo:
                return CompactLogoScrollView(viewModel: viewModel, content: content)
            case .cinematic:
                return CinematicScrollView(viewModel: viewModel, content: content)
            }
        case .musicArtist:
            return CompactPosterScrollView(viewModel: viewModel, content: content)
        default:
            return SimpleScrollView(viewModel: viewModel, content: content)
        }
    }

    @ViewBuilder
    private var innerBody: some View {
        scrollContainerView(viewModel: viewModel) {
            scrollContentView
        }
        .eraseToAnyView()
    }

    private var isDownloadActionDisabled: Bool {
        viewModel.state != .content || viewModel.downloadActionAvailability == .pending
    }

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .content:
                if viewModel.item.type == .episode {
                    innerBody
                } else {
                    innerBody
                        .navigationTitle(viewModel.item.displayTitle)
                }
            case let .error(error):
                ErrorView(error: error)
            case .initial, .refreshing:
                ProgressView()
            }
        }
        .animation(.linear(duration: 0.1), value: viewModel.state)
        .errorMessage($viewModel.mediaSourceSelectionError)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let record = viewModel.offlineRecord {
                ToolbarItem(placement: .navigationBarTrailing) {
                    DownloadTaskButton(
                        item: record.item,
                        selection: .userSelected(record.mediaSource)
                    )
                }
            } else if viewModel.downloadActionAvailability != .unavailable {
                if let seriesViewModel = viewModel as? SeriesItemViewModel {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        SeriesDownloadButton(viewModel: seriesViewModel)
                            .disabled(isDownloadActionDisabled)
                    }
                } else if let downloadItem = viewModel.playButtonItem {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        DownloadTaskButton(
                            item: downloadItem,
                            selection: viewModel.mediaSourceSelectionIntent
                        )
                        .disabled(isDownloadActionDisabled)
                    }
                }
            }
        }
        .if(!viewModel.isOffline) { view in
            view.refreshable {
                viewModel.send(.refresh)
            }
        }
        .onFirstAppear {
            if !viewModel.isOffline {
                viewModel.send(.refresh)
            }
        }
    }
}

extension PlatformItemView {

    struct ItemManagementButtons: View {

        @Router
        private var router

        @StoredValue(.User.enableItemDeletion)
        private var enableItemDeletion

        @StateObject
        private var viewModel: ItemEditorViewModel

        @State
        private var isPresentingDeleteConfirmation = false

        private var canDelete: Bool {
            enableItemDeletion && viewModel.item.canDelete == true
        }

        private var canRefreshMetadata: Bool {
            viewModel.item.canEditMetadata
        }

        init(item: BaseItemDto) {
            self._viewModel = StateObject(wrappedValue: ItemEditorViewModel(item: item))
        }

        private var refreshButton: some View {
            Button {
                viewModel.refreshMetadata(
                    metadataRefreshMode: .fullRefresh,
                    imageRefreshMode: .fullRefresh,
                    replaceMetadata: true,
                    replaceImages: true,
                    regenerateTrickplay: false
                )
            } label: {
                Label(L10n.refreshMetadata, systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }

        private var deleteButton: some View {
            Button(role: .destructive) {
                isPresentingDeleteConfirmation = true
            } label: {
                Label(L10n.delete, systemImage: "trash")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }

        @ViewBuilder
        private var styledRefreshButton: some View {
            if #available(iOS 26.0, *) {
                refreshButton
                    .buttonStyle(.glass)
            } else {
                refreshButton
                    .buttonStyle(.material)
            }
        }

        @ViewBuilder
        private var styledDeleteButton: some View {
            if #available(iOS 26.0, *) {
                deleteButton
                    .tint(.red)
                    .buttonStyle(.glassProminent)
            } else {
                deleteButton
                    .buttonStyle(.tintedMaterial(tint: .red, foregroundColor: .primary))
            }
        }

        @ViewBuilder
        var body: some View {
            if canRefreshMetadata || canDelete {
                VStack(spacing: 12) {
                    if canRefreshMetadata {
                        styledRefreshButton
                    }

                    if canDelete {
                        styledDeleteButton
                    }
                }
                .disabled(viewModel.background.is(.updating))
                .edgePadding(.horizontal)
                .confirmationDialog(
                    L10n.deleteItemConfirmationMessage,
                    isPresented: $isPresentingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(L10n.confirm, role: .destructive, action: viewModel.delete)
                    Button(L10n.cancel, role: .cancel) {}
                }
                .onReceive(viewModel.events) { event in
                    switch event {
                    case .deleted:
                        UIDevice.feedback(.success)
                        router.pop()
                    case .metadataRefreshStarted:
                        UIDevice.feedback(.success)
                    case .updated:
                        break
                    }
                }
                .errorMessage($viewModel.error)
            }
        }
    }
}

extension PlatformItemView {

    struct PlainScrollView<Content: View>: ScrollContainerView {

        private let content: Content

        init(
            viewModel: ItemViewModel,
            @ViewBuilder content: () -> Content
        ) {
            self.content = content()
        }

        var body: some View {
            ScrollView(showsIndicators: false) {
                content
                    .padding(.top, PlatformItemView.detailSectionSpacing)
                    .edgePadding(.bottom)
            }
        }
    }
}
