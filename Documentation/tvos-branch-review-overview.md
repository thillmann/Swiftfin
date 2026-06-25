# tvOS Branch Review Overview

This is the main tracking document for reviewing the changes on `codex/tvos-liquid-glass` against `origin/main`.

## Review standard

Review the branch as a coherent tvOS change, not as 140 isolated files. For each row, read the branch diff and enough surrounding code, callers, models, resources, and project configuration to understand the behavior. Follow established repository patterns unless changing them produces a clear improvement. Shared and iOS code should be checked when the branch touches it, while tvOS remains the primary scope.

### Intent and correctness

- Confirm the change serves a current requirement and preserves expected behavior, including empty, loading, error, cancellation, retry, and boundary states.
- Look for incorrect assumptions, stale or inconsistent state, race conditions, unsafe indexing or casts, force unwraps, swallowed errors, and unintended behavior changes.
- Check that API contracts, navigation and deep links, persistence, caching, playback lifecycle, and failure recovery remain coherent across call sites.
- Prefer explicit invariants and exhaustive state modelling over loosely related booleans or impossible state combinations.

### Simplicity and readability

- Remove dead, unreachable, obsolete, duplicated, speculative, and compatibility code that is no longer required.
- Prefer the smallest clear design; avoid unnecessary layers, wrappers, type erasure, indirection, generic machinery, and premature abstraction.
- Keep names precise, control flow easy to follow, functions and types focused, and comments reserved for intent or non-obvious constraints.
- Consolidate repeated policy, but do not extract tiny code merely to reduce line count. Preserve useful locality.
- Remove debug scaffolding, commented-out code, stale TODOs, unused resources, and temporary workarounds whose reason no longer applies.

### Swift and concurrency

- Use value semantics where appropriate, narrow access control, immutable state by default, and types that make invalid states difficult to represent.
- Verify ownership and lifetimes: avoid retain cycles, accidental long-lived tasks, duplicated sources of truth, and closures that capture more than necessary.
- Prefer structured concurrency. Ensure task ownership, actor isolation, cancellation, priority, and error propagation match the operation's lifecycle.
- Keep UI-facing mutations main-actor-safe, but keep blocking I/O and expensive non-UI work off the main actor.
- Avoid detached or unstructured tasks unless their independent lifetime is deliberate and documented by the design.

### SwiftUI architecture and state

- Use the narrowest suitable state mechanism: local `@State`, parent-owned `@Binding`, explicit model inputs, and environment injection for genuinely shared services.
- Keep views declarative and focused. Move business rules, networking, persistence, and expensive transformations out of `body`.
- Prefer composition and stable view structure over giant views, `AnyView`, parallel presentation flags, or wholesale tree replacement for small state changes.
- Use `.task` or `.task(id:)` for view-lifecycle async work, treat cancellation as normal, and represent loading, content, empty, and error states explicitly.
- Verify navigation and presentation have a single owner and that state restoration, dismissal, and repeated presentation behave predictably.

### tvOS interaction and accessibility

- Verify focus order, focus restoration, default focus, directional navigation, remote press handling, menus, scrolling, and back behavior.
- Ensure focused and unfocused states are visually clear without relying only on color; avoid focus traps and controls that are reachable but unusable.
- Prefer standard SwiftUI controls and focus APIs where they provide the required behavior. Custom gestures and controls must preserve expected system interaction.
- Check accessibility labels, values, traits, grouping, reading order, contrast, reduced-motion behavior, and meaningful alternatives for icon-only controls and images.
- Check layouts at realistic television viewing distances, with long localized text, safe areas, overlays, and content of varying dimensions.

### Performance and resources

- Keep list and grid identity stable, use lazy containers for large collections, and avoid unnecessary broad observation or repeated view invalidation.
- Keep sorting, filtering, image work, formatting, I/O, and other meaningful computation out of hot render and interaction paths.
- Check image request and cache behavior, task cancellation, memory growth, media-player ownership, and cleanup when views disappear or playback changes.
- Prefer responsive feedback and avoid synchronous main-thread work that could cause focus, scrolling, animation, or playback hitches.
- Validate that assets have correct scale, appearance, rendering intent, target membership, naming, and no redundant variants.

### Platform configuration, privacy, and compatibility

- Review deployment-target availability, tvOS/iOS conditional compilation, API deprecations, and behavior differences in shared code.
- Treat entitlements, Info.plist keys, URL schemes, deep links, Top Shelf configuration, target membership, build settings, and schemes as production code.
- Request only required capabilities and permissions. Do not log secrets, tokens, personal data, or sensitive media/account information.
- Keep user-facing text localized and avoid assembling sentences from fragments. Check formatting and plural-sensitive content where applicable.

### Maintainability and verification

- Check nearby tests and previews, and add or update focused coverage when behavior is testable and the risk justifies it.
- Review deleted and renamed files for stale references, duplicate replacements, project-file residue, obsolete assets, and migration or compatibility impact.
- Keep changes scoped: avoid unrelated churn, formatting noise, and public API expansion without a concrete need.
- Use static inspection and focused checks during review. Per repository guidance, do not run builds by default; request or record any build, simulator, performance, or device verification still needed.

Apply worthwhile fixes as part of the review rather than recording actionable findings for later. A file is only **Reviewed and actioned** once its diff and relevant context have been inspected, all in-scope findings have been resolved, and any verification performed or still required is clear.

## How to use this tracker

Update the **Review status** as work progresses:

- ⬜ Not reviewed
- 🟨 In progress
- ✅ Reviewed and actioned
- 🔁 Follow-up needed
- ⏭️ Skipped / not applicable

Leave **Notes** empty when everything found was resolved during review. Use it only for remaining follow-ups, intentionally deferred work, unresolved questions, or a brief explanation of why no action was taken. Link to a dedicated review note, commit, or follow-up chat when more context is needed.

## Scope snapshot

- Branch: `codex/tvos-liquid-glass`
- Comparison base: `origin/main`
- Commits ahead when created: 82
- Changed entries: 140
- Working tree when created: clean
- Created: 2026-06-21

## File review tracker

| Change         | File                                                                                                      | Review status   | Notes |
| -------------- | --------------------------------------------------------------------------------------------------------- | --------------- | ----- |
| Modified       | `Shared/App/SwiftfinApp+configure.swift`                                                                  | ⬜ Not reviewed | —     |
| Modified       | `Shared/Components/AttributeBadge.swift`                                                                  | ⬜ Not reviewed | —     |
| Modified       | `Shared/Components/ButtonStyles/SupplementTitleButtonStyle.swift`                                         | ⬜ Not reviewed | —     |
| Modified       | `Shared/Components/PosterImage.swift`                                                                     | ⬜ Not reviewed | —     |
| Modified       | `Shared/Components/PosterIndicators/ProgressIndicator.swift`                                              | ⬜ Not reviewed | —     |
| Modified       | `Shared/Components/RotateContentView.swift`                                                               | ⬜ Not reviewed | —     |
| Modified       | `Shared/Coordinators/Navigation/NavigationRoute/NavigationRoute+Media.swift`                              | ⬜ Not reviewed | —     |
| Modified       | `Shared/Coordinators/Navigation/NavigationRoute/NavigationRoute+Settings.swift`                           | ⬜ Not reviewed | —     |
| Modified       | `Shared/Coordinators/Tabs/MainTabView.swift`                                                              | ✅ Reviewed and actioned | Top Shelf routing path inspected; no remaining code changes. |
| Modified       | `Shared/Extensions/EdgeInsets.swift`                                                                      | ⬜ Not reviewed | —     |
| Modified       | `Shared/Extensions/JellyfinAPI/BaseItemDto/BaseItemDto+Poster.swift`                                      | ⬜ Not reviewed | —     |
| Modified       | `Shared/Extensions/JellyfinAPI/BaseItemDto/BaseItemDto.swift`                                             | ⬜ Not reviewed | —     |
| Modified       | `Shared/Extensions/UIImage.swift`                                                                         | ⬜ Not reviewed | —     |
| Modified       | `Shared/Extensions/ViewExtensions/TypeViewRegistry/PosterOverlayRegistry.swift`                           | ⬜ Not reviewed | —     |
| Modified       | `Shared/Extensions/ViewExtensions/ViewExtensions.swift`                                                   | ⬜ Not reviewed | —     |
| Modified       | `Shared/Objects/MediaPlayerManager/MediaPlayerItem/MediaPlayerItem+Build.swift`                           | ⬜ Not reviewed | —     |
| Modified       | `Shared/Objects/MediaPlayerManager/MediaPlayerItem/MediaPlayerItem.swift`                                 | ⬜ Not reviewed | —     |
| Modified       | `Shared/Objects/MediaPlayerManager/MediaPlayerManager.swift`                                              | ⬜ Not reviewed | —     |
| Modified       | `Shared/Objects/MediaPlayerManager/MediaPlayerProxy/MediaPlayerProxy+VLC.swift`                           | ⬜ Not reviewed | —     |
| Modified       | `Shared/Objects/MediaPlayerManager/Supplements/Components/SupplementPosterButton.swift`                   | ⬜ Not reviewed | —     |
| Modified       | `Shared/Objects/MediaPlayerManager/Supplements/EpisodeMediaPlayerQueue.swift`                             | ⬜ Not reviewed | —     |
| Modified       | `Shared/Objects/MediaPlayerManager/Supplements/MediaChaptersSupplement.swift`                             | ⬜ Not reviewed | —     |
| Modified       | `Shared/Objects/MediaPlayerManager/Supplements/MediaInfoSupplement.swift`                                 | ⬜ Not reviewed | —     |
| Modified       | `Shared/Objects/MediaPlayerManager/Supplements/MediaPeopleSupplement.swift`                               | ⬜ Not reviewed | —     |
| Modified       | `Shared/Objects/MediaPlayerManager/Supplements/PlaybackRateMediaPlayerSupplement.swift`                   | ⬜ Not reviewed | —     |
| Added          | `Shared/Services/SeerrClient.swift`                                                                       | ⬜ Not reviewed | —     |
| Added          | `Shared/Services/SeerrIntegration.swift`                                                                  | ⬜ Not reviewed | —     |
| Modified       | `Shared/Services/SwiftfinDefaults.swift`                                                                  | ⬜ Not reviewed | —     |
| Modified       | `Shared/Strings/Strings.swift`                                                                            | ⬜ Not reviewed | Touched only to add `skipIntro` for the video-player review; broader strings diff not reviewed. |
| Modified       | `Shared/ViewModels/HomeViewModel.swift`                                                                   | ✅ Reviewed and actioned | Reviewed Top Shelf cache write integration and resume filtering; no remaining code changes. |
| Modified       | `Shared/ViewModels/ItemViewModel/ItemViewModel.swift`                                                     | ⬜ Not reviewed | —     |
| Modified       | `Shared/ViewModels/ItemViewModel/SeasonItemViewModel.swift`                                               | ⬜ Not reviewed | —     |
| Modified       | `Shared/ViewModels/ItemViewModel/SeriesItemViewModel.swift`                                               | ⬜ Not reviewed | —     |
| Modified       | `Shared/ViewModels/LibraryViewModel/LatestInLibraryViewModel.swift`                                       | ⬜ Not reviewed | —     |
| Modified       | `Shared/ViewModels/LibraryViewModel/NextUpLibraryViewModel.swift`                                         | ⬜ Not reviewed | —     |
| Modified       | `Shared/ViewModels/LibraryViewModel/PagingLibraryViewModel.swift`                                         | ⬜ Not reviewed | —     |
| Modified       | `Shared/ViewModels/LibraryViewModel/RecentlyAddedViewModel.swift`                                         | ⬜ Not reviewed | —     |
| Modified       | `Shared/ViewModels/MediaViewModel/MediaType.swift`                                                        | ⬜ Not reviewed | —     |
| Modified       | `Shared/ViewModels/MediaViewModel/MediaViewModel.swift`                                                   | ⬜ Not reviewed | —     |
| Modified       | `Shared/ViewModels/ProgramsViewModel.swift`                                                               | ⬜ Not reviewed | —     |
| Modified       | `Shared/ViewModels/SearchViewModel.swift`                                                                 | ⬜ Not reviewed | —     |
| Modified       | `Shared/Views/MediaView/Components/MediaItem.swift`                                                       | ⬜ Not reviewed | —     |
| Modified       | `Shared/Views/MediaView/MediaView.swift`                                                                  | ⬜ Not reviewed | —     |
| Added          | `Shared/Views/SeerrRequestView.swift`                                                                     | ⬜ Not reviewed | —     |
| Modified       | `Shared/Views/SettingsView/CustomizeSettingsView.swift`                                                   | ⬜ Not reviewed | —     |
| Modified       | `Shared/Views/SettingsView/DebugSettingsView.swift`                                                       | ⬜ Not reviewed | —     |
| Added          | `Shared/Views/SettingsView/SeerrSettingsView.swift`                                                       | ⬜ Not reviewed | —     |
| Modified       | `Shared/Views/SettingsView/SettingsView.swift`                                                            | ⬜ Not reviewed | —     |
| Modified       | `Shared/Views/SettingsView/VideoPlayerSettingsView.swift`                                                 | ⬜ Not reviewed | —     |
| Modified       | `Shared/Views/VideoPlayer/Components/PlaybackProgress/SplitTimestamp.swift`                               | ✅ Reviewed and actioned | —     |
| Modified       | `Shared/Views/VideoPlayer/Components/Toolbar/ActionButtons/VideoPlayer+ActionButtons.swift`               | ✅ Reviewed and actioned | —     |
| Added          | `Shared/Views/VideoPlayer/Components/Toolbar/SkipIntroButton.swift`                                       | ✅ Reviewed and actioned | Localized the button label through `L10n.skipIntro`. |
| Modified       | `Shared/Views/VideoPlayer/Components/Toolbar/VideoPlayer+Toolbar.swift`                                   | ✅ Reviewed and actioned | —     |
| Modified       | `Shared/Views/VideoPlayer/VideoPlayerContainerView/SupplementContainerView.swift`                         | ✅ Reviewed and actioned | —     |
| Modified       | `Shared/Views/VideoPlayer/VideoPlayerContainerView/VideoPlayerContainerView.swift`                        | ✅ Reviewed and actioned | —     |
| Added          | `Swiftfin tvOS Top Shelf/Resources/Info.plist`                                                            | ✅ Reviewed and actioned | —     |
| Added          | `Swiftfin tvOS Top Shelf/Resources/Swiftfin-tvOS-Top-Shelf.entitlements`                                  | 🔁 Follow-up needed | App group is hard-coded to `group.timo.jellyfin.swiftfin`; confirm production/shared signing identifier before release. |
| Added          | `Swiftfin tvOS Top Shelf/TopShelfContentProvider.swift`                                                   | ✅ Reviewed and actioned | —     |
| Modified       | `Swiftfin tvOS/App/SwiftfinApp.swift`                                                                     | ✅ Reviewed and actioned | —     |
| Modified       | `Swiftfin tvOS/Components/CapsuleSlider.swift`                                                            | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Components/CinematicBackgroundView.swift`                                                  | ⬜ Not reviewed | —     |
| Added          | `Swiftfin tvOS/Components/CinematicItemHeroView.swift`                                                    | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Components/CinematicItemSelector.swift`                                                    | ⬜ Not reviewed | —     |
| Added          | `Swiftfin tvOS/Components/CirclePosterButton.swift`                                                       | ⬜ Not reviewed | —     |
| Added          | `Swiftfin tvOS/Components/FeatureButton.swift`                                                            | ⬜ Not reviewed | —     |
| Added          | `Swiftfin tvOS/Components/HeroScrollView.swift`                                                           | ⬜ Not reviewed | —     |
| Deleted        | `Swiftfin tvOS/Components/LandscapePosterProgressBar.swift`                                               | ⬜ Not reviewed | —     |
| Renamed (100%) | `Swiftfin tvOS/Views/PagingLibraryView/Components/ListRow.swift → Swiftfin tvOS/Components/ListRow.swift` | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Components/ListRowMenu.swift`                                                              | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Components/PosterButton.swift`                                                             | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Components/PosterHStack.swift`                                                             | ⬜ Not reviewed | —     |
| Added          | `Swiftfin tvOS/Components/PosterVGrid.swift`                                                              | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Components/VideoPlayerSlider.swift`                                                        | ✅ Reviewed and actioned | —     |
| Modified       | `Swiftfin tvOS/Extensions/View/View-tvOS.swift`                                                           | ⬜ Not reviewed | —     |
| Added          | `Swiftfin tvOS/Resources/Assets.xcassets/seerr.monochrome.imageset/Contents.json`                         | ⬜ Not reviewed | —     |
| Added          | `Swiftfin tvOS/Resources/Assets.xcassets/seerr.monochrome.imageset/seerr.monochrome.svg`                  | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Resources/Info.plist`                                                                      | ✅ Reviewed and actioned | —     |
| Added          | `Swiftfin tvOS/Resources/Swiftfin-tvOS.entitlements`                                                      | 🔁 Follow-up needed | App group is hard-coded to `group.timo.jellyfin.swiftfin`; confirm production/shared signing identifier before release. |
| Added          | `Swiftfin tvOS/Services/TopShelfDeepLinkStore.swift`                                                      | ✅ Reviewed and actioned | —     |
| Added          | `Swiftfin tvOS/Services/TopShelfResumeCache.swift`                                                        | 🔁 Follow-up needed | Runtime app group constant is hard-coded to `group.timo.jellyfin.swiftfin`; keep in sync with the production entitlement decision. |
| Added          | `Swiftfin tvOS/Services/TopShelfResumeCacheWriter.swift`                                                  | ✅ Reviewed and actioned | Fixed unauthenticated Top Shelf artwork URLs by including the query API key. |
| Modified       | `Swiftfin tvOS/Views/HomeView/Components/CinematicRecentlyAddedView.swift`                                | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/HomeView/Components/CinematicResumeItemView.swift`                                   | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/HomeView/Components/LatestInLibraryView.swift`                                       | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/HomeView/Components/NextUpView.swift`                                                | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/HomeView/Components/RecentlyAddedView.swift`                                         | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/HomeView/HomeView.swift`                                                             | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/CollectionItemContentView.swift`                                            | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/AboutView/AboutView.swift`                                       | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/AboutView/Components/AboutViewCard.swift`                        | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/AboutView/Components/ImageCard.swift`                            | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/AboutView/Components/MediaSourcesCard.swift`                     | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/AboutView/Components/OverviewCard.swift`                         | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/AboutView/Components/RatingsCard.swift`                          | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/ActionButtonHStack/ActionButtonHStack.swift`                     | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/ActionButtonHStack/Components/TrailerMenu.swift`                 | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/AttributeHStack.swift`                                           | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/CastAndCrewHStack.swift`                                         | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/EpisodeSelector/Components/EpisodeCard.swift`                    | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/EpisodeSelector/Components/EpisodeContent.swift`                 | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/EpisodeSelector/Components/ErrorCard.swift`                      | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/EpisodeSelector/Components/HStacks/EpisodeHStack.swift`          | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/EpisodeSelector/Components/HStacks/SeasonHStack.swift`           | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/EpisodeSelector/Components/LoadingCard.swift`                    | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/EpisodeSelector/EpisodeSelector.swift`                           | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/OverviewView.swift`                                              | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/PlayButton/PlayButton.swift`                                     | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/Components/SpecialFeaturesHStack.swift`                                     | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/ItemView.swift`                                                             | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/MovieItemContentView.swift`                                                 | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/ScrollViews/CinematicScrollView.swift`                                      | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/SeriesItemContentView.swift`                                                | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ItemView/SimpleItemContentView.swift`                                                | ⬜ Not reviewed | —     |
| Added          | `Swiftfin tvOS/Views/MediaView/SeerrTrendingView.swift`                                                   | ⬜ Not reviewed | —     |
| Added          | `Swiftfin tvOS/Views/MediaView/SeerrUpcomingView.swift`                                                   | ⬜ Not reviewed | —     |
| Deleted        | `Swiftfin tvOS/Views/PagingLibraryView/Components/LibraryRow.swift`                                       | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/PagingLibraryView/PagingLibraryView.swift`                                           | ⬜ Not reviewed | —     |
| Added          | `Swiftfin tvOS/Views/ProgramsView/Components/ProgramOverlay.swift`                                        | ⬜ Not reviewed | —     |
| Deleted        | `Swiftfin tvOS/Views/ProgramsView/Components/ProgramProgressOverlay.swift`                                | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/ProgramsView/ProgramsView.swift`                                                     | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/SearchView.swift`                                                                    | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin tvOS/Views/VideoPlayer/PlaybackControls/Components/PlaybackControls+PressHandling.swift`        | ✅ Reviewed and actioned | —     |
| Modified       | `Swiftfin tvOS/Views/VideoPlayer/PlaybackControls/Components/PlaybackProgress.swift`                      | ✅ Reviewed and actioned | Restored a LIVE badge fallback when live channel playback has no program schedule dates. |
| Modified       | `Swiftfin tvOS/Views/VideoPlayer/PlaybackControls/PlaybackControls.swift`                                 | ✅ Reviewed and actioned | —     |
| Modified       | `Swiftfin.xcodeproj/project.pbxproj`                                                                      | 🔁 Follow-up needed | Top Shelf target/embed wiring reviewed; extension bundle id is hard-coded to `timo.jellyfin.swiftfin.TopShelf`, which only matches local ignored signing overrides. Confirm production bundle-id strategy. |
| Modified       | `Swiftfin.xcodeproj/xcshareddata/xcschemes/Swiftfin tvOS.xcscheme`                                        | ✅ Reviewed and actioned | Only Xcode upgrade metadata changed. |
| Modified       | `Swiftfin.xcodeproj/xcshareddata/xcschemes/Swiftfin.xcscheme`                                             | ⬜ Not reviewed | —     |
| Modified       | `Swiftfin/Views/SearchView.swift`                                                                         | ⬜ Not reviewed | —     |
| Modified       | `Translations/en.lproj/Localizable.strings`                                                               | ⬜ Not reviewed | Touched only to add `skipIntro` for the video-player review; broader localization diff not reviewed. |
