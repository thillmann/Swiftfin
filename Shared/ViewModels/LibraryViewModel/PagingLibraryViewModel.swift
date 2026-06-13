//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import IdentifiedCollections
import JellyfinAPI
import UIKit

/// Magic number for page sizes
private let DefaultPageSize = 50

/// A protocol for items to conform to if they may be present within a library.
///
/// Similar to `Identifiable`, but `unwrappedIDHashOrZero` is an `Int`: the hash of the underlying `id`
/// value if it is not optional, or if it is optional it must return the hash of the wrapped value,
/// or 0 otherwise:
///
///     struct Item: LibraryIdentifiable {
///         var id: String? { "id" }
///
///         var unwrappedIDHashOrZero: Int {
///             // Gets the `hashValue` of the `String.hashValue`, not `Optional.hashValue`.
///             id?.hashValue ?? 0
///         }
///     }
///
/// This is necessary because if the `ID` is optional, then `Optional.hashValue` will be used instead
/// and result in differing hashes.
///
/// This also helps if items already conform to `Identifiable`, but has an optionally-typed `id`.
protocol LibraryIdentifiable: Identifiable {

    var unwrappedIDHashOrZero: Int { get }
}

// TODO: fix how `hasNextPage` is determined
//       - some subclasses might not have "paging" and only have one call. This can be solved with
//         a check if elements were actually appended to the set but that requires a redundant get
// TODO: this doesn't allow "scrolling" to an item if index > pageSize
//       on refresh. Should make bidirectional/offset index start?
//       - use startIndex/index ranges instead of pages
//       - source of data doesn't guarantee that all items in 0 ..< startIndex exist
// TODO: have `filterViewModel` be private to the parent and the `get_` overrides recieve the
//       current filters as a parameter
// TODO: need an ID

/*
 Note: if `rememberSort == true`, then will override given filters with stored sorts
       for parent ID. This was just easy. See `PagingLibraryView` notes for lack of
       `rememberSort` observation and `StoredValues.User.libraryFilters` for TODO
       on remembering other filters.
 */

@MainActor
class PagingLibraryViewModel<Element: Poster>: ViewModel, Eventful, Stateful {

    // MARK: Event

    enum Event {
        case gotRandomItem(Element)
    }

    // MARK: Action

    enum Action: Equatable {
        case error(ErrorMessage)
        case refresh
        case getNextPage
        case getRandomItem
    }

    // MARK: BackgroundState

    enum BackgroundState: Hashable {
        case gettingNextPage
    }

    // MARK: State

    enum State: Hashable {
        case content
        case error(ErrorMessage)
        case initial
        case refreshing
    }

    @Published
    var backgroundStates: Set<BackgroundState> = []
    @Published
    var pagingError: ErrorMessage?
    @Published
    private(set) var items: [Element]

    @Published
    var state: State = .initial

    /// - Keys: the `hashValue` of the `Element.ID`
    var elements: IdentifiedArray<Int, Element> {
        IdentifiedArray(
            items,
            id: \.unwrappedIDHashOrZero,
            uniquingIDsWith: { x, _ in x }
        )
    }

    final let filterViewModel: FilterViewModel?
    final let parent: (any LibraryParent)?

    final var events: AnyPublisher<Event, Never> {
        eventSubject
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    let pageSize: Int
    private(set) var currentPage = -1
    private(set) var hasNextPage = true
    private(set) var isLoading = false

    private let eventSubject: PassthroughSubject<Event, Never> = .init()
    private let isStatic: Bool
    private var shouldLoadNextPageAfterCurrentLoad = false

    // tasks

    private var pagingTask: AnyCancellable?
    private var nextPageTask: AnyCancellable?
    private var randomItemTask: AnyCancellable?

    // MARK: init

    // static
    init(
        _ data: some Collection<Element>,
        parent: (any LibraryParent)? = nil
    ) {
        self.filterViewModel = nil
        self.items = Array(data)
        self.isStatic = true
        self.hasNextPage = false
        self.pageSize = DefaultPageSize
        self.parent = parent

        super.init()

        Notifications[.didDeleteItem]
            .publisher
            .receive(on: RunLoop.main)
            .sink { id in
                self.items.removeAll { $0.unwrappedIDHashOrZero == id.hashValue }
            }
            .store(in: &cancellables)
    }

    convenience init(
        title: String,
        id: String?,
        _ data: some Collection<Element>
    ) {
        self.init(
            data,
            parent: TitledLibraryParent(
                displayTitle: title,
                id: id
            )
        )
    }

    // paging
    init(
        parent: (any LibraryParent)? = nil,
        filters: ItemFilterCollection? = nil,
        pageSize: Int = DefaultPageSize
    ) {
        self.items = []
        self.isStatic = false
        self.pageSize = pageSize
        self.parent = parent

        if var filters {
            if let id = parent?.id, Defaults[.Customization.Library.rememberSort] {
                // TODO: see `StoredValues.User.libraryFilters` for TODO
                //       on remembering other filters

                let storedFilters = StoredValues[.User.libraryFilters(parentID: id)]

                filters.sortBy = storedFilters.sortBy
                filters.sortOrder = storedFilters.sortOrder
            }

            self.filterViewModel = .init(
                parent: parent,
                currentFilters: filters
            )
        } else {
            self.filterViewModel = nil
        }

        super.init()

        Notifications[.didDeleteItem]
            .publisher
            .sink { id in
                self.items.removeAll { $0.unwrappedIDHashOrZero == id.hashValue }
            }
            .store(in: &cancellables)

        if let filterViewModel {
            filterViewModel.$currentFilters
                .dropFirst()
                .debounce(for: 1, scheduler: RunLoop.main)
                .removeDuplicates()
                .sink { [weak self] _ in
                    guard let self else { return }

                    Task { @MainActor in
                        self.send(.refresh)
                    }
                }
                .store(in: &cancellables)
        }
    }

    convenience init(
        title: String,
        id: String?,
        filters: ItemFilterCollection? = nil,
        pageSize: Int = DefaultPageSize
    ) {
        self.init(
            parent: TitledLibraryParent(
                displayTitle: title,
                id: id
            ),
            filters: filters,
            pageSize: pageSize
        )
    }

    // MARK: respond

    @MainActor
    func respond(to action: Action) -> State {

        if action == .refresh, isStatic {
            return .content
        }

        switch action {
        case let .error(error):

            Task { @MainActor in
                items.removeAll()
                pagingError = nil
            }

            return .error(error)
        case .refresh:

            pagingTask?.cancel()
            nextPageTask?.cancel()
            nextPageTask = nil
            randomItemTask?.cancel()

            filterViewModel?.getQueryFilters()
            pagingError = nil

            pagingTask = Task { [weak self] in
                guard let self else { return }

                do {
                    try await self.refresh()

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.state = .content
                    }
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.send(.error(.init(error.localizedDescription)))
                    }
                }
            }
            .asAnyCancellable()

            return .refreshing
        case .getNextPage:

            guard hasNextPage else { return state }

            backgroundStates.insert(.gettingNextPage)

            pagingTask = Task { [weak self] in
                do {
                    try await self?.getNextPage()

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self?.backgroundStates.remove(.gettingNextPage)
                        self?.state = .content
                    }
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self?.backgroundStates.remove(.gettingNextPage)
                        self?.state = .error(.init(error.localizedDescription))
                    }
                }
            }
            .asAnyCancellable()

            return .content
        case .getRandomItem:

            randomItemTask = Task { [weak self] in
                do {
                    guard let randomItem = try await self?.getRandomItem() else { return }

                    guard !Task.isCancelled else { return }

                    self?.eventSubject.send(.gotRandomItem(randomItem))
                } catch {
                    // TODO: when a general toasting mechanism is implemented, add
                    //       background errors for errors from other background tasks
                }
            }
            .asAnyCancellable()

            return state
        }
    }

    // MARK: refresh

    final func refresh() async throws {
        items.removeAll()
        currentPage = -1
        hasNextPage = !isStatic
        shouldLoadNextPageAfterCurrentLoad = false

        try await getNextPage()
    }

    /// Gets the next page of items or immediately returns if
    /// there is not a next page.
    ///
    /// See `get(page:)` for the conditions that determine
    /// if there is a next page or not.
    final func getNextPage() async throws {
        guard hasNextPage else { return }

        if isLoading {
            shouldLoadNextPageAfterCurrentLoad = true
            return
        }

        isLoading = true

        let nextPage = currentPage + 1

        do {
            let pageItems = try await get(page: nextPage)

            currentPage = nextPage
            hasNextPage = pageItems.count >= pageSize
            appendUnique(pageItems)
            isLoading = false

            if shouldLoadNextPageAfterCurrentLoad {
                shouldLoadNextPageAfterCurrentLoad = false
                try await getNextPage()
            }
        } catch {
            isLoading = false
            shouldLoadNextPageAfterCurrentLoad = false
            throw error
        }
    }

    final func loadNextPageIfNeeded(currentItem: Element) {
        guard hasNextPage, nextPageTask == nil, !isLoading else { return }
        guard let currentIndex = items.firstIndex(where: { item in
            item.unwrappedIDHashOrZero == currentItem.unwrappedIDHashOrZero
        }) else { return }

        let threshold = Swift.max(items.count - pageSize, 0)
        guard currentIndex >= threshold else { return }

        nextPageTask = Task { [weak self] in
            guard let self else { return }
            defer { self.nextPageTask = nil }

            do {
                try await self.getNextPage()

                guard !Task.isCancelled else { return }

                self.pagingError = nil
            } catch {
                guard !Task.isCancelled else { return }

                self.pagingError = .init(error.localizedDescription)
            }
        }
        .asAnyCancellable()
    }

    final func retryNextPage() {
        guard hasNextPage, nextPageTask == nil, !isLoading else { return }

        pagingError = nil

        nextPageTask = Task { [weak self] in
            guard let self else { return }
            defer { self.nextPageTask = nil }

            do {
                try await self.getNextPage()

                guard !Task.isCancelled else { return }

                self.pagingError = nil
            } catch {
                guard !Task.isCancelled else { return }

                self.pagingError = .init(error.localizedDescription)
            }
        }
        .asAnyCancellable()
    }

    /// Gets the items at the given page. If the number of items
    /// is less than `pageSize`, then it is inferred that
    /// there is not a next page and subsequent calls to `getNextPage`
    /// will immediately return.
    func get(page: Int) async throws -> [Element] {
        []
    }

    /// Gets a random item from `elements`. Override if item should
    /// come from another source instead.
    func getRandomItem() async throws -> Element? {
        items.randomElement()
    }

    private func appendUnique(_ newItems: [Element]) {
        var seenIDs = Set(items.map(\.unwrappedIDHashOrZero))

        for item in newItems where seenIDs.insert(item.unwrappedIDHashOrZero).inserted {
            items.append(item)
        }
    }
}
