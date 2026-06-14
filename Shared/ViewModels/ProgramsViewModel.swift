//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI

final class ProgramsViewModel: ViewModel, Stateful {

    enum ProgramSection: CaseIterable {
        case kids
        case movies
        case news
        case recommended
        case series
        case sports
    }

    // MARK: Action

    enum Action: Equatable {
        case error(ErrorMessage)
        case refresh
    }

    // MARK: State

    enum State: Hashable {
        case content
        case error(ErrorMessage)
        case initial
        case refreshing
    }

    @Published
    private(set) var kids: [BaseItemDto] = []
    @Published
    private(set) var movies: [BaseItemDto] = []
    @Published
    private(set) var news: [BaseItemDto] = []
    @Published
    private(set) var recommended: [BaseItemDto] = []
    @Published
    private(set) var series: [BaseItemDto] = []
    @Published
    private(set) var sports: [BaseItemDto] = []
    @Published
    private(set) var channels: [BaseItemDto] = []
    @Published
    private(set) var channelsByID: [String: BaseItemDto] = [:]

    @Published
    var state: State = .initial

    private var currentRefreshTask: AnyCancellable?

    var hasNoResults: Bool {
        [
            kids,
            movies,
            news,
            recommended,
            series,
            sports,
            channels,
        ].allSatisfy(\.isEmpty)
    }

    func respond(to action: Action) -> State {
        switch action {
        case let .error(error):
            return .error(error)
        case .refresh:
            currentRefreshTask?.cancel()

            currentRefreshTask = Task { [weak self] in
                guard let self else { return }

                do {
                    let sections = try await getItemSections()
                    let channels: [BaseItemDto]
                    do {
                        channels = try await getChannels()
                    } catch {
                        logger.warning("Unable to load Live TV channels: \(error.localizedDescription)")
                        channels = []
                    }

                    let channelsByID: [String: BaseItemDto]
                    do {
                        channelsByID = try await getChannelsByID(
                            for: sections.values.flatMap(\.self),
                            merging: channels
                        )
                    } catch {
                        logger.warning("Unable to load Live TV channels for programs: \(error.localizedDescription)")
                        channelsByID = Self.channelsByID(from: channels)
                    }

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.kids = sections[.kids] ?? []
                        self.movies = sections[.movies] ?? []
                        self.news = sections[.news] ?? []
                        self.recommended = sections[.recommended] ?? []
                        self.series = sections[.series] ?? []
                        self.sports = sections[.sports] ?? []
                        self.channels = channels
                        self.channelsByID = channelsByID

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
        }
    }

    func channel(for program: BaseItemDto) -> BaseItemDto? {
        guard let channelID = program.channelID else { return nil }
        return channelsByID[channelID]
    }

    private func getItemSections() async throws -> [ProgramSection: [BaseItemDto]] {
        try await withThrowingTaskGroup(
            of: (ProgramSection, [BaseItemDto]).self,
            returning: [ProgramSection: [BaseItemDto]].self
        ) { group in

            // sections
            for section in ProgramSection.allCases {
                group.addTask {
                    let items = try await self.getPrograms(for: section)
                    return (section, items)
                }
            }

            // recommended
            group.addTask {
                let items = try await self.getRecommendedPrograms()
                return (ProgramSection.recommended, items)
            }

            var programs: [ProgramSection: [BaseItemDto]] = [:]

            while let items = try await group.next() {
                programs[items.0] = items.1
            }

            return programs
        }
    }

    private func getRecommendedPrograms() async throws -> [BaseItemDto] {

        var parameters = Paths.GetRecommendedProgramsParameters()
        parameters.fields = .MinimumFields
            .appending(.channelInfo)
        parameters.isAiring = true
        parameters.limit = 20

        let request = Paths.getRecommendedPrograms(parameters: parameters)
        let response = try await send(request)

        return response.value.items ?? []
    }

    private func getPrograms(for section: ProgramSection) async throws -> [BaseItemDto] {

        var parameters = Paths.GetLiveTvProgramsParameters()
        parameters.fields = .MinimumFields
            .appending(.channelInfo)
        parameters.hasAired = false
        parameters.limit = 20

        parameters.isKids = section == .kids
        parameters.isMovie = section == .movies
        parameters.isNews = section == .news
        parameters.isSeries = section == .series
        parameters.isSports = section == .sports

        let request = Paths.getLiveTvPrograms(parameters: parameters)
        let response = try await send(request)

        return response.value.items ?? []
    }

    private func getChannels() async throws -> [BaseItemDto] {

        var parameters = Paths.GetLiveTvChannelsParameters()
        parameters.fields = .MinimumFields
        parameters.enableFavoriteSorting = true
        parameters.enableUserData = true
        parameters.isAddCurrentProgram = true
        parameters.limit = 100
        parameters.sortBy = [ItemSortBy.name]
        parameters.sortOrder = .ascending

        let request = Paths.getLiveTvChannels(parameters: parameters)
        let response = try await userSession.client.send(request)

        return Self.sortChannels(response.value.items ?? [])
    }

    private func getChannelsByID(
        for programs: [BaseItemDto],
        merging channels: [BaseItemDto]
    ) async throws -> [String: BaseItemDto] {

        let channelIDs = Array(Set(programs.compactMap(\.channelID)))
        var channelsByID = Self.channelsByID(from: channels)

        guard channelIDs.isNotEmpty else { return channelsByID }

        var parameters = Paths.GetItemsParameters()
        parameters.fields = .MinimumFields
        parameters.ids = channelIDs

        let request = Paths.getItems(parameters: parameters)
        let response = try await userSession.client.send(request)

        for channel in response.value.items ?? [] {
            guard let id = channel.id else { continue }
            channelsByID[id] = channel
        }

        return channelsByID
    }

    private static func channelsByID(from channels: [BaseItemDto]) -> [String: BaseItemDto] {
        channels.reduce(into: [:]) { partialResult, channel in
            guard let id = channel.id else { return }
            partialResult[id] = channel
        }
    }

    private static func sortChannels(_ channels: [BaseItemDto]) -> [BaseItemDto] {
        channels.sorted { lhs, rhs in
            let lhsIsFavorite = lhs.userData?.isFavorite == true
            let rhsIsFavorite = rhs.userData?.isFavorite == true

            if lhsIsFavorite != rhsIsFavorite {
                return lhsIsFavorite
            }

            switch (lhs.userData?.lastPlayedDate, rhs.userData?.lastPlayedDate) {
            case let (lhsLastPlayed?, rhsLastPlayed?) where lhsLastPlayed != rhsLastPlayed:
                return lhsLastPlayed > rhsLastPlayed
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
        }
    }
}
