import Defaults
import Foundation

@MainActor
enum PlatformSettingsMigration {
    static func migrate() {
        let suite = UserDefaults.currentUserSuite
        func needsMigration(_ destination: String, _ source: [String]) -> Bool {
            suite.object(forKey: destination) == nil && source.contains { suite.object(forKey: $0) != nil }
        }
        if needsMigration("subtitleConfiguration", ["subtitleColor", "subtitleFontName", "subtitleSize"]) {
            Defaults[.VideoPlayer.Subtitle.configuration] = .init(
                color: Defaults[.VideoPlayer.Subtitle.subtitleColor],
                fontName: Defaults[.VideoPlayer.Subtitle.subtitleFontName],
                size: Defaults[.VideoPlayer.Subtitle.subtitleSize]
            )
        }
        if needsMigration("posterConfiguration", ["showPosterLabels", "showFavoritedIndicator", "showProgressIndicator", "showUnplayedIndicator", "showPlayedIndicator", "useSeriesBackdrop"]) {
            var configuration = PosterConfiguration.default
            configuration.isTitlePresented = Defaults[.Customization.showPosterLabels]
            configuration.unplayedStyle = Defaults[.Customization.Indicators.showUnplayed]
            configuration.useSeriesLandscapeBackdrop = Defaults[.Customization.Episodes.useSeriesLandscapeBackdrop]
            if !Defaults[.Customization.Indicators.showFavorited] { configuration.indicators.remove(.favorited) }
            if !Defaults[.Customization.Indicators.showProgress] { configuration.indicators.remove(.progress) }
            if !Defaults[.Customization.Indicators.showPlayed] { configuration.indicators.remove(.played) }
            Defaults[.Customization.Poster.configuration] = configuration
        }
        if needsMigration("libraryStyle", ["libraryViewType", "libraryPosterType", "listColumnCount"]) {
            Defaults[.Customization.Library.style] = .init(
                displayType: Defaults[.Customization.Library.displayType],
                posterDisplayType: Defaults[.Customization.Library.posterType],
                listColumnCount: Defaults[.Customization.Library.listColumnCount]
            )
        }
    }
}
