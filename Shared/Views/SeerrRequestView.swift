//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct SeerrRequestView: View {

    @Environment(\.dismiss)
    private var dismiss

    @StateObject
    private var viewModel: SeerrRequestViewModel
    #if os(tvOS)
    @FocusState
    private var isRequestButtonFocused: Bool
    #endif

    private let onComplete: () -> Void

    init(item: SeerrClient.MediaResult, onComplete: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: SeerrRequestViewModel(item: item))
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            #if os(tvOS)
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            #endif

            NavigationStack {
                Group {
                    switch viewModel.loadState {
                    case .loading:
                        ProgressView()
                    case let .failed(message):
                        ErrorView(error: ErrorMessage(message))
                    case .loaded:
                        content
                    }
                }
                #if os(tvOS)
                .frame(width: 1200, height: 820)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
                #endif
                .toolbar {}
                    .task {
                        await viewModel.load()
                    }
                    .alert(
                        L10n.requestFailed,
                        isPresented: Binding(
                            get: { viewModel.errorMessage != nil },
                            set: { if !$0 { viewModel.errorMessage = nil } }
                        )
                    ) {
                        Button(L10n.ok) {
                            viewModel.errorMessage = nil
                        }
                    } message: {
                        Text(viewModel.errorMessage ?? "")
                    }
            }
        }
    }

    private var content: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    requestSection

                    if viewModel.isTV {
                        seasonsSection
                            .padding(.bottom, 10)
                    }

                    optionsSection
                }
                .edgePadding(.horizontal)
                .edgePadding(.vertical)
            }
            #if os(tvOS)
            .defaultFocus($isRequestButtonFocused, true, priority: .userInitiated)
            #endif
        }
    }

    private var requestSection: some View {
        HStack {
            HStack(spacing: 8) {
                if let releaseDate = viewModel.releaseDateText {
                    Text(releaseDate)
                }
                if let rating = viewModel.ratingText {
                    Text("•")
                    Image(systemName: "star.fill")
                        .font(.caption)
                    Text(rating)
                }
            }
            .font(.caption)
            .foregroundStyle(.primary)

            Spacer()
            Button(viewModel.requestButtonTitle) {
                Task {
                    let result = await viewModel.submit()
                    switch result {
                    case .success:
                        onComplete()
                        dismiss()
                    case let .failure(error):
                        viewModel.errorMessage = error.localizedDescription
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSubmitting || !viewModel.canSubmit)
            #if os(tvOS)
                .focused($isRequestButtonFocused)
            #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.title)
                .font(.title2.weight(.semibold))
                .lineLimit(2)

            DotHStack(padding: 4) {
                Text(viewModel.mediaKindText)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let requestStatusText = viewModel.requestStatusText {
                    Text(requestStatusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Defaults[.accentColor], in: Capsule())
                }

                if let mediaGenresText = viewModel.mediaGenresText {
                    Text(mediaGenresText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }

            if let overview = viewModel.overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }
        }
    }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.seasons)
                .font(.headline)

            Menu {
                Button(L10n.allSeasons) {
                    allSeasonsBinding.wrappedValue = true
                }
                Button(L10n.noSeasons) {
                    allSeasonsBinding.wrappedValue = false
                }
                Divider()

                ForEach(viewModel.seasons) { season in
                    let seasonNumber = season.seasonNumber ?? -1
                    let isSelected = viewModel.selectedSeasonNumbers.contains(seasonNumber)
                    Button {
                        guard let seasonNumber = season.seasonNumber else { return }
                        if viewModel.selectedSeasonNumbers.contains(seasonNumber) {
                            viewModel.selectedSeasonNumbers.remove(seasonNumber)
                        } else {
                            viewModel.selectedSeasonNumbers.insert(seasonNumber)
                        }
                    } label: {
                        HStack {
                            Text(season.displayName)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(L10n.seasonSelection)
                    Spacer()
                    Text(L10n.selectedCountOfTotal(
                        viewModel.selectedSeasonNumbers.count,
                        viewModel.selectableSeasonNumbers.count
                    ))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private var allSeasonsBinding: Binding<Bool> {
        Binding(
            get: {
                viewModel.selectableSeasonNumbers.isNotEmpty &&
                    viewModel.selectedSeasonNumbers.count == viewModel.selectableSeasonNumbers.count
            },
            set: { enabled in
                if enabled {
                    viewModel.selectedSeasonNumbers = Set(viewModel.selectableSeasonNumbers)
                } else {
                    viewModel.selectedSeasonNumbers.removeAll()
                }
            }
        )
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.advanced)
                .font(.headline)

            if viewModel.profiles.isNotEmpty {
                Menu {
                    ForEach(viewModel.profiles) { profile in
                        Button(profile.displayName) {
                            viewModel.selectedProfileID = profile.id
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(L10n.qualityProfile)
                        Spacer()
                        Text(viewModel.selectedProfileName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if viewModel.rootFolders.isNotEmpty {
                Picker(L10n.rootFolder, selection: $viewModel.selectedRootFolder) {
                    ForEach(viewModel.rootFolders) { folder in
                        Text(folder.path).tag(Optional(folder.path))
                    }
                }
            }

            if viewModel.languageProfiles.isNotEmpty {
                Picker(L10n.languageProfile, selection: $viewModel.selectedLanguageProfileID) {
                    ForEach(viewModel.languageProfiles) { profile in
                        Text(profile.languageDisplayName).tag(Optional(profile.id))
                    }
                }
            }

            Toggle(L10n.requestIn4K, isOn: $viewModel.is4K)
        }
    }
}

@MainActor
final class SeerrRequestViewModel: ObservableObject {
    enum LoadState {
        case loading
        case loaded
        case failed(String)
    }

    @Published
    var loadState: LoadState = .loading
    @Published
    var errorMessage: String?
    @Published
    var isSubmitting = false

    @Published
    var services: [SeerrClient.ServiceInstance] = []
    @Published
    var profiles: [SeerrClient.ServiceProfile] = []
    @Published
    var rootFolders: [SeerrClient.ServiceRootFolder] = []
    @Published
    var languageProfiles: [SeerrClient.ServiceProfile] = []
    @Published
    var seasons: [SeerrClient.Season] = []

    @Published
    var selectedServiceID: Int?
    @Published
    var selectedProfileID: Int?
    @Published
    var selectedRootFolder: String?
    @Published
    var selectedLanguageProfileID: Int?
    @Published
    var selectedSeasonNumbers: Set<Int> = []
    @Published
    var is4K = false

    private let item: SeerrClient.MediaResult
    private var movieDetails: SeerrClient.MovieDetails?
    private var tvDetails: SeerrClient.TVDetails?

    init(item: SeerrClient.MediaResult) {
        self.item = item
    }

    var isTV: Bool {
        item.mediaType == .tv
    }

    var title: String {
        movieDetails?.title ?? tvDetails?.name ?? item.title ?? item.name ?? L10n.unknown
    }

    var overview: String? {
        movieDetails?.overview ?? tvDetails?.overview ?? item.overview
    }

    private var rawReleaseDateText: String? {
        movieDetails?.releaseDate ?? tvDetails?.firstAirDate ?? item.releaseDate ?? item.firstAirDate
    }

    var releaseDateText: String? {
        guard let value = rawReleaseDateText else { return nil }

        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"

        guard let date = parser.date(from: value) else { return value }

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    var ratingText: String? {
        let value = movieDetails?.voteAverage ?? tvDetails?.voteAverage ?? item.voteAverage
        guard let value else { return nil }
        return String(format: "%.1f", value)
    }

    var mediaKindText: String {
        isTV ? L10n.series : L10n.movie
    }

    var mediaGenresText: String? {
        let genres = (movieDetails?.genres ?? tvDetails?.genres ?? [])
            .compactMap(\.name)
            .filter { !$0.isEmpty }

        guard genres.isNotEmpty else { return nil }
        return genres.joined(separator: ", ")
    }

    var requestStatus: SeerrClient.MediaStatus? {
        movieDetails?.mediaInfo?.mediaStatus ?? tvDetails?.mediaInfo?.mediaStatus ?? item.mediaInfo?.mediaStatus
    }

    var requestStatusText: String? {
        guard let requestStatus, requestStatus != .unknown else { return nil }
        return requestStatus.displayText
    }

    var selectableSeasonNumbers: [Int] {
        seasons.compactMap(\.seasonNumber)
    }

    var isAlreadyRequested: Bool {
        switch requestStatus {
        case .pending, .processing, .available:
            true
        default:
            false
        }
    }

    var requestButtonTitle: String {
        isAlreadyRequested ? L10n.seerrStatusRequested : L10n.request
    }

    var canSubmit: Bool {
        if isAlreadyRequested {
            return false
        }

        if isTV {
            return selectedSeasonNumbers.isNotEmpty
        }
        return true
    }

    var selectedProfileName: String {
        guard let selectedProfileID,
              let profile = profiles.first(where: { $0.id == selectedProfileID })
        else {
            return L10n.selectProfile
        }

        return profile.displayName
    }

    func load() async {
        loadState = .loading

        switch item.mediaType {
        case .movie:
            let detailsResult = await SeerrClient.movieDetails(id: item.id)
            let serviceResult = await SeerrClient.radarrServices()
            apply(detailsResult: detailsResult, serviceResult: serviceResult)
        case .tv:
            let detailsResult = await SeerrClient.tvDetails(id: item.id)
            let serviceResult = await SeerrClient.sonarrServices()
            apply(detailsResult: detailsResult, serviceResult: serviceResult)
        default:
            loadState = .failed(L10n.unsupportedMediaTypeForSeerrRequest)
        }
    }

    func loadServiceDetails() async {
        guard let selectedServiceID else { return }
        guard let selectedService = services.first(where: { $0.id == selectedServiceID }) else { return }

        // Base options are often already present in the service list payload.
        applyServiceOptions(
            activeProfileID: selectedService.activeProfileId,
            activeDirectory: selectedService.activeDirectory,
            profiles: selectedService.profiles ?? selectedService.qualityProfiles,
            rootFolders: selectedService.rootFolders,
            languageProfiles: selectedService.languageProfiles
        )

        let result: Result<SeerrClient.ServiceInstanceDetails, SeerrClient.ProbeError> = if isTV {
            await SeerrClient.sonarrServiceDetails(id: selectedServiceID)
        } else {
            await SeerrClient.radarrServiceDetails(id: selectedServiceID)
        }

        switch result {
        case let .success(details):
            applyServiceOptions(
                activeProfileID: details.activeProfileId,
                activeDirectory: details.activeDirectory,
                profiles: details.profiles ?? details.qualityProfiles,
                rootFolders: details.rootFolders,
                languageProfiles: details.languageProfiles
            )
        case .failure:
            break
        }

        if profiles.isEmpty {
            let profilesResult: Result<[SeerrClient.ServiceProfile], SeerrClient.ProbeError> = if isTV {
                await SeerrClient.availableSonarrProfiles(id: selectedServiceID)
            } else {
                await SeerrClient.availableRadarrProfiles(id: selectedServiceID)
            }

            if case let .success(fallbackProfiles) = profilesResult, fallbackProfiles.isNotEmpty {
                profiles = fallbackProfiles
                if selectedProfileID == nil || !fallbackProfiles.contains(where: { $0.id == selectedProfileID }) {
                    selectedProfileID = fallbackProfiles.first?.id
                }
            }
        }

        if profiles.isEmpty,
           let activeProfileID = selectedService.activeProfileId
        {
            profiles = [.init(id: activeProfileID, name: selectedService.activeProfileName ?? L10n.default)]
            if selectedProfileID == nil {
                selectedProfileID = activeProfileID
            }
        }
    }

    func submit() async -> Result<Void, SeerrClient.ProbeError> {
        guard let mediaType = item.mediaType else {
            return .failure(.init(message: L10n.unsupportedMediaType))
        }

        let requestMediaType: SeerrClient.RequestMediaType
        switch mediaType {
        case .movie:
            requestMediaType = .movie
        case .tv:
            requestMediaType = .tv
        case .person:
            return .failure(.init(message: L10n.personRequestsNotSupported))
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let seasonsValue: SeerrClient.RequestedSeasons? = if isTV {
            .specific(Array(selectedSeasonNumbers).sorted())
        } else {
            nil
        }

        let result = await SeerrClient.request(
            mediaType: requestMediaType,
            mediaID: item.id,
            options: .init(
                seasons: seasonsValue,
                is4K: is4K,
                serverID: selectedServiceID,
                profileID: selectedProfileID,
                rootFolder: selectedRootFolder,
                languageProfileID: selectedLanguageProfileID,
                userID: nil
            )
        )

        switch result {
        case .success:
            return .success(())
        case let .failure(error):
            return .failure(error)
        }
    }

    private func apply(
        detailsResult: Result<SeerrClient.MovieDetails, SeerrClient.ProbeError>,
        serviceResult: Result<[SeerrClient.ServiceInstance], SeerrClient.ProbeError>
    ) {
        switch detailsResult {
        case let .success(details):
            movieDetails = details
        case let .failure(error):
            loadState = .failed(error.localizedDescription)
            return
        }

        switch serviceResult {
        case let .success(services):
            self.services = services
            self.selectedServiceID = services.first(where: { $0.isDefault == true })?.id ?? services.first?.id
        case let .failure(error):
            loadState = .failed(error.localizedDescription)
            return
        }

        loadState = .loaded

        Task {
            await loadServiceDetails()
        }
    }

    private func apply(
        detailsResult: Result<SeerrClient.TVDetails, SeerrClient.ProbeError>,
        serviceResult: Result<[SeerrClient.ServiceInstance], SeerrClient.ProbeError>
    ) {
        switch detailsResult {
        case let .success(details):
            tvDetails = details
            seasons = details.seasons ?? []
            selectedSeasonNumbers = Set(seasons.compactMap(\.seasonNumber))
        case let .failure(error):
            loadState = .failed(error.localizedDescription)
            return
        }

        switch serviceResult {
        case let .success(services):
            self.services = services
            self.selectedServiceID = services.first(where: { $0.isDefault == true })?.id ?? services.first?.id
        case let .failure(error):
            loadState = .failed(error.localizedDescription)
            return
        }

        loadState = .loaded

        Task {
            await loadServiceDetails()
        }
    }

    private func applyServiceOptions(
        activeProfileID: Int?,
        activeDirectory: String?,
        profiles: [SeerrClient.ServiceProfile]?,
        rootFolders: [SeerrClient.ServiceRootFolder]?,
        languageProfiles: [SeerrClient.ServiceProfile]?
    ) {
        if let profiles, profiles.isNotEmpty {
            self.profiles = profiles
        }

        if let rootFolders, rootFolders.isNotEmpty {
            self.rootFolders = rootFolders
        }

        if let languageProfiles, languageProfiles.isNotEmpty {
            self.languageProfiles = languageProfiles
        }

        if selectedProfileID == nil {
            selectedProfileID = activeProfileID ?? self.profiles.first?.id
        } else if self.profiles.isNotEmpty, !self.profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = self.profiles.first?.id
        }

        if selectedRootFolder == nil {
            selectedRootFolder = activeDirectory ?? self.rootFolders.first?.path
        }

        if selectedLanguageProfileID == nil {
            selectedLanguageProfileID = self.languageProfiles.first?.id
        }
    }
}

private extension SeerrClient.Season {

    var displayName: String {
        name ?? L10n.seasonNumber(seasonNumber ?? 0)
    }
}

private extension SeerrClient.ServiceProfile {

    var displayName: String {
        name ?? L10n.profileNumber(id)
    }

    var languageDisplayName: String {
        name ?? L10n.languageNumber(id)
    }
}
