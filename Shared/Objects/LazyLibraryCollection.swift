//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Factory
import Foundation
import JellyfinAPI
import SwiftUI

enum LazyLibraryCollectionError: LocalizedError {
    case missingUserSession

    var errorDescription: String? {
        switch self {
        case .missingUserSession:
            "Missing Jellyfin user session."
        }
    }
}

enum LazyLibraryContentFilter {
    case movies
    case tvShows

    var itemTypes: [BaseItemKind] {
        switch self {
        case .movies:
            [.movie]
        case .tvShows:
            [.series]
        }
    }
}

@MainActor
final class LazyLibraryCollection<T>: ObservableObject, RandomAccessCollection {
    typealias Element = T
    typealias Index = Int
    typealias PageLoader = (_ page: Int, _ pageSize: Int, _ existingItems: [T]) async throws -> [T]

    @Published
    private var elements: [T]
    private let pageLoader: PageLoader?

    @Published
    private(set) var currentPage = -1
    @Published
    private(set) var hasNextPage: Bool
    @Published
    private(set) var isLoading = false
    let pageSize: Int

    private var shouldLoadNextPageAfterCurrentLoad = false

    init() {
        self.elements = []
        self.pageLoader = nil
        self.hasNextPage = false
        self.pageSize = 42
    }

    init(_ elements: some Sequence<T>) {
        self.elements = Array(elements)
        self.pageLoader = nil
        self.hasNextPage = false
        self.pageSize = 42
    }

    init(count: Int, generator: (Int) -> T) {
        self.elements = (0 ..< count).map(generator)
        self.pageLoader = nil
        self.hasNextPage = false
        self.pageSize = 42
    }

    init(
        pageSize: Int = 42,
        pageLoader: @escaping PageLoader
    ) {
        self.elements = []
        self.pageLoader = pageLoader
        self.hasNextPage = true
        self.pageSize = pageSize
    }

    var startIndex: Index {
        elements.startIndex
    }

    var endIndex: Index {
        elements.endIndex
    }

    subscript(position: Index) -> Element {
        elements[position]
    }

    func index(after i: Index) -> Index {
        elements.index(after: i)
    }

    func index(before i: Index) -> Index {
        elements.index(before: i)
    }

    func append(contentsOf newElements: some Sequence<T>) {
        elements.append(contentsOf: newElements)
    }

    func removeAll(where shouldRemove: (T) throws -> Bool) rethrows {
        try elements.removeAll(where: shouldRemove)
    }

    func loadNextPage() async throws {
        guard let pageLoader, hasNextPage else { return }

        if isLoading {
            shouldLoadNextPageAfterCurrentLoad = true
            return
        }

        isLoading = true

        let nextPage = currentPage + 1
        let existingItems = elements

        do {
            let pageItems = try await pageLoader(nextPage, pageSize, existingItems)

            currentPage = nextPage
            hasNextPage = pageItems.count >= pageSize
            append(contentsOf: pageItems)
            isLoading = false

            if shouldLoadNextPageAfterCurrentLoad {
                shouldLoadNextPageAfterCurrentLoad = false
                try await loadNextPage()
            }
        } catch {
            isLoading = false
            shouldLoadNextPageAfterCurrentLoad = false
            throw error
        }
    }

    func loadNextPageIfNeeded(currentIndex: Int, prefetchItemCount: Int? = nil) async throws {
        let threshold = Swift.max(count - (prefetchItemCount ?? pageSize), 0)

        guard isEmpty || currentIndex >= threshold else { return }

        try await loadNextPage()
    }

    func loadNextPageIfNeeded(
        currentItem: T,
        prefetchItemCount: Int? = nil,
        matches: (T, T) -> Bool
    ) async throws {
        guard let currentIndex = firstIndex(where: { matches($0, currentItem) }) else { return }

        try await loadNextPageIfNeeded(
            currentIndex: currentIndex,
            prefetchItemCount: prefetchItemCount
        )
    }

    func loadInitialPages(_ pageCount: Int = 2) async throws {
        guard isEmpty else { return }

        for _ in 0 ..< pageCount {
            guard hasNextPage else { return }

            try await loadNextPage()
        }
    }

    func refresh() async throws {
        elements.removeAll()
        currentPage = -1
        hasNextPage = pageLoader != nil

        try await loadNextPage()
    }
}

extension LazyLibraryCollection where Element == BaseItemDto {

    func loadNextPageIfNeeded(
        currentItem: BaseItemDto,
        prefetchItemCount: Int? = nil
    ) async throws {
        try await self.loadNextPageIfNeeded(
            currentItem: currentItem,
            prefetchItemCount: prefetchItemCount,
            matches: { item, currentItem in
                item.id == currentItem.id
            }
        )
    }

    static func jellyfinItems(
        parent: (any LibraryParent)? = nil,
        contentFilter: LazyLibraryContentFilter? = nil,
        pageSize: Int = 42,
        configure: @escaping (_ parameters: inout Paths.GetItemsParameters, _ existingItems: [BaseItemDto]) -> Void = { _, _ in }
    ) -> Self {
        Self(pageSize: pageSize) { page, pageSize, existingItems in
            guard let userSession = Container.shared.currentUserSession() else {
                throw LazyLibraryCollectionError.missingUserSession
            }

            var parameters = Paths.GetItemsParameters()
            parameters.enableUserData = true
            parameters.fields = .MinimumFields
            parameters.includeItemTypes = BaseItemKind.supportedCases
            parameters.sortOrder = [.ascending]
            parameters.sortBy = [ItemSortBy.name]
            parameters.isRecursive = (parent as? BaseItemDto)?.isRecursiveCollection ?? true
            parameters.limit = pageSize
            parameters.startIndex = page * pageSize

            if let parent {
                parameters = parent.setParentParameters(parameters)
            }

            if let contentFilter {
                parameters.includeItemTypes = contentFilter.itemTypes
            }

            configure(&parameters, existingItems)

            let request = Paths.getItems(parameters: parameters)
            let response = try await userSession.client.send(request)

            return (response.value.items ?? [])
                .filter { item in
                    if let collectionType = item.collectionType {
                        return CollectionType.supportedCases.contains(collectionType)
                    }

                    return true
                }
                .map { item in
                    if parent?.libraryType == .folder, item.type == .collectionFolder {
                        return item.mutating(\.type, with: .folder)
                    }

                    return item
                }
        }
    }
}
