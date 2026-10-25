# Swiftfin: project background and agent handoff

Updated 2026-10-25 (Australia/Brisbane). This document describes the local fork at `c08594e3a` on `main`, plus the uncommitted changes listed below. It was reconstructed from current source and local Git history; it is not a new product specification or evidence of fresh runtime testing. Recheck the working tree before continuing.

## Goal and background

Swiftfin is a native Swift/SwiftUI client for Jellyfin on iPhone, iPad, and Apple TV. Jellyfin supplies the user's media, library metadata, accounts, and playback services. The upstream project emphasizes native Apple UI and broad direct-play support.

This fork builds on that foundation with a cinematic, artwork-led experience, platform-specific navigation and interactions, Seerr discovery and requests, durable offline downloads on iOS/iPadOS, configurable server connections, and an additional Aether playback backend. The established direction is to preserve those features and the refined platform UI while integrating upstream improvements to shared data, sessions, playback, and dependencies.

The custom UI is intentional product work. Do not assume upstream shared screens should replace it simply because both implementations exist. Equally, the fork should use the newer shared infrastructure rather than restore obsolete backend implementations to keep an old screen compiling.

The original custom work accumulated on `codex/tvos-liquid-glass`. A cumulative integration commit, `09f21c92e`, brought the final source tree from `3043dbbae` onto recorded upstream `2229d6f61`. The historical integration record says 198 source commits were retained in source/backup history. Those branch names are historical context, not instructions to switch branches; this checkout is currently on `main`.

## Major design decisions

### 1. Share infrastructure; retain the platform experiences

- `Shared/` owns services, models, persistence, routing, much of the playback stack, and reusable views. `Swiftfin/` and `Swiftfin tvOS/` own their respective platform experiences.
- The custom home, detail, search, poster, and paging-library implementations remain active. Names such as `PlatformItemView`, `PlatformSearchView`, `PlatformPosterButton`, and `PlatformPagingLibraryView` distinguish them from upstream shared equivalents. This coexistence is deliberate, not sufficient evidence of dead code.
- Keep the upstream `UserSession`, shared `ItemStore`, routing, and player protocols. Platform views receive item/user-data updates through the shared session/store integration and snapshot notifications. Updates should preserve collection identity, scroll position, and focus; deleted items must still disappear.
- Offline metadata must remain usable independently of online item-store invalidation.

### 2. Cinematic presentation with native interactions

- iOS/iPadOS retain the resume carousel, large backdrops, loading placeholders and fades, compact/cinematic detail layouts, episode rails, metadata, and source-selection actions. Phone and iPad layout/search behavior differ intentionally.
- iOS 26+ uses native tabs and a search-role tab; older supported iOS versions use the legacy tab view. The phone search field belongs at the tab container level, with shared query state and explicit keyboard dismissal. See `MainTabView.swift` and `PlatformSearchView.swift`.
- tvOS retains cinematic resume/recently-added heroes, animated backgrounds, studio/network/genre rails, season pills, and remote-friendly controls. Focus identity, episode selection, scroll restoration, and return-from-playback behavior are part of the design, not incidental implementation details.
- Glass styling has compatibility fallbacks. Keep artwork sizing, poster shadows, detail-header blur/fades, and loading appearance consistent with existing platform components.
- Avoid subscribing a whole home screen to frame-rate backdrop scroll updates; iOS keeps persistent carousel/backdrop state separately for this reason.

### 3. Discovery complements the Jellyfin library

- Optional Seerr integration supplies discovery, upcoming titles/episodes, and requests. Unified results match discovered media to the user's Jellyfin library so available content can lead to its local item.
- Seerr is available only when enabled and configured with a valid server URL and API key. Keys are held by the keychain service; do not move credentials into source or ordinary settings.
- Preserve genre discovery and the existing ALL-selected genre filtering semantics, plus tvOS studio/network browsing. Library browsing and discovery are related but do not share identical availability or request behavior.

### 4. Offline downloads are durable user data

- The fork intentionally retains downloads even though the integrated upstream changes removed the old download feature. Download UI is iOS/iPadOS-specific; coordination and metadata live in shared code.
- Preserve `DownloadRecord` identity/Codable compatibility, storage paths, background-session handling, recovery, cancellation cleanup, version selection, and offline progress reconciliation. Do not clear stores or reset preferences to solve migration problems.
- Startup and user selection must allow offline access to downloaded media without requiring a successful online server check. Metadata refresh should not block offline entry.
- Downloads target finite movie/episode files. The current manager explicitly rejects unsupported cases such as disc folders, live/infinite streams, and offline HLS; do not imply every playable source is downloadable.
- `OfflineMetadataDecoder` narrowly repairs legacy missing/null `UserData.Key` values after the Jellyfin SDK update. It must preserve existing keys, progress, filenames, subtitle maps, and large integer byte counts while continuing to reject malformed metadata.
- An AVPlayer preference may fall back to VLC for downloaded media with unsupported containers or subtitle sidecars. That per-item choice must not rewrite the user's stored player preference.

### 5. Multiple playback engines behind one manager

- `MediaPlayerManager` and the `MediaPlayerProxy` protocols coordinate AVPlayer, VLC, MPV, and Aether. VLC is the default; MPV availability is controlled by an experimental setting. Aether is an additional selectable backend, not a replacement for the others.
- Persisted player names are compatibility contracts: `native`/`avPlayer` decode to AVPlayer, `swiftfin`/`vlc` to VLC, and `mpv`/`aether` remain stable.
- Aether uses its own direct-play/transcoding/subtitle profiles and an adapter to the upstream layout, lifecycle, and PiP interfaces. Preserve rate across play/seek/reload, actual probed track-ID mapping, sidecar subtitles, viewport/subtitle layout, and throttled clock updates. Its package is pinned to 6.6.0 in this checkpoint.
- Retain source/version hydration and recovery, authenticated media URLs, and fallback behavior alongside upstream Live TV, track, reporting, and transcoding-cleanup fixes. Offline playback must not expose online bitrate/version controls.
- Returning from PiP must keep the active player alive. The recent fix starts `VideoPlayer` only on first appearance and preserves an existing session on foreground refresh when both user and server match. A real account/server change must still tear down playback. Foreground connection evaluation remains scheduled separately.

### 6. Connection resolution belongs to the session infrastructure

- Server connections have URLs, priority, interface rules (any/Wi-Fi/cellular), and optional Wi-Fi SSID matching.
- `ServerConnectionManager` monitors network context; the session manager owns connection evaluation. Rule edits and explicit evaluation refresh the cached context, derive SSID requirements from current rules, and reject stale asynchronous lookups/probes.
- Avoid adding a competing connection resolver inside a screen or making online connectivity a prerequisite for offline entry.

### 7. Preserve settings and platform integration

- Existing compact/cinematic item preferences use the preserved `itemViewType` storage key through `platformItemViewType`; upstream media-item preferences use separate storage. Grouped-default migrations fill missing destinations without overwriting explicit choices.
- Keep existing per-library preferences, legacy poster/subtitle settings, and persisted backend names compatible.
- Apple TV Top Shelf is a separate extension with a shared app-group resume cache and display/play deep links. Preserve target dependency, extension embedding, entitlements, identifiers, and user-context checks together.
- The project currently targets iOS 18.6 and tvOS 26.1. Treat the project settings and resolved packages as more precise than the broad README badges or older player documentation.
- Both app targets explicitly embed CoreStore. Do not remove that phase as redundant: it was added after a missing-framework startup diagnosis. The historical integration pinned CoreStore revision `4cf205a57b57eda24d88571a9aee4023b5c3981b` for Xcode 27 compatibility.
- Keep localization references and generated `Shared/Strings/Strings.swift` synchronized. The integration retained the union of source/upstream English keys; untranslated additions fall back to English.

## Where to start in the code

Paths below are repository-relative.

| Area | Entry points |
| --- | --- |
| Startup and accounts | `Swiftfin/App/SwiftfinApp.swift`, `Swiftfin tvOS/App/SwiftfinApp.swift`, `Shared/Coordinators/Root/`, `Shared/Services/UserSession/` |
| Tabs/navigation | `Shared/Coordinators/Tabs/MainTabView.swift`, `TabItem.swift`, `Shared/Coordinators/Navigation/` |
| Home and details | Both platform `Views/HomeView/` and `Views/ItemView/` directories; `Shared/ViewModels/HomeViewModel.swift` |
| Apple TV cinematic UI | `Swiftfin tvOS/Components/CinematicItemHeroView.swift`, `HeroScrollView.swift`, `PlatformCinematicItemSelector.swift` |
| Shared item state | `Shared/Objects/ItemStore/`, `Shared/Services/UserSession/UserSession+Items.swift`, `UserSession+ItemChanges.swift` |
| Discovery | `Shared/Services/SeerrClient.swift`, `SeerrIntegration.swift`, `SeerrLibraryMatcher.swift`, `GenreMediaSource.swift`, `Shared/Objects/UnifiedMediaResult.swift` |
| Download/offline | `Shared/Services/DownloadManager.swift`, `DownloadRecord.swift`, `OfflineMetadataDecoder.swift`, `Swiftfin/Views/DownloadListView.swift`, `Shared/Objects/MediaPlayerManager/MediaPlayerItem/MediaPlayerItem+Offline.swift` |
| Playback | `Shared/Objects/MediaPlayerManager/`, `Shared/Objects/VideoPlayerType/`, `Shared/Views/VideoPlayer/`, platform playback controls |
| Connections | `Shared/Services/ServerConnectionManager.swift`, `Shared/ViewModels/ServerConnectionViewModel.swift`, `Shared/Objects/ServerConnection.swift` |
| Preferences/persistence | `Shared/Services/SwiftfinDefaults.swift`, `SwiftfinDefaults+PlatformMigration.swift`, `Shared/SwiftfinStore/` |
| Top Shelf | `Swiftfin tvOS Top Shelf/TopShelfContentProvider.swift`, `Swiftfin tvOS/Services/TopShelf*` |
| Project/dependencies | `Swiftfin.xcodeproj/project.pbxproj`, its workspace's `xcshareddata/swiftpm/Package.resolved`, `XcodeConfig/`, `SwiftfinMacros/`, `PreferencesView/` |

## Current checkpoint and unfinished work

The latest committed changes are:

| Commit | Purpose |
| --- | --- |
| `c08594e3a` | Preserve active playback/session when returning from PiP. |
| `70c2e7d1d` | Fix iPhone search-tab activation and detail-header blur. |
| `d1b0b4b4f` | Refresh connection context after rule changes and reject stale work. Also intentionally remove the completed rebase documents. |
| `108871b6a` / `c64ca03d7` | Embed CoreStore and record physical-device provisioning diagnosis. |
| `ec0c1fdc5` / `1b33cc2c4` | Integration compatibility fixes and recorded successful simulator builds. |

At the start of this documentation task, six files already had uncommitted changes. Preserve and review them before editing:

- `Shared/Components/ErrorView.swift`: adds opt-in server selection for an active session. The action explicitly signs out to reach server selection and disables controls while doing so.
- `Shared/Views/MediaView/MediaView.swift`, `Swiftfin/Views/HomeView/HomeView.swift`, and `Swiftfin tvOS/Views/HomeView/HomeView.swift`: opt into that error-recovery action.
- `Swiftfin.xcodeproj/project.pbxproj`: local signing-team/bundle-ID changes and project ordering changes.
- `Swiftfin tvOS/Resources/Info.plist`: key ordering changes, retaining the app-group identifier.

These edits were not introduced or validated by the documentation task. They are not yet a committed completion checkpoint. This handoff and its `AGENTS.md` pointer are additional documentation changes.

### Validation evidence and limits

The following is historical evidence from the October 12 integration notes, not a fresh build of the current tree:

- Debug arm64 iOS and tvOS simulator builds passed with Xcode 27.0 (27A266a), including the Top Shelf extension. iOS/iPadOS startup was observed in simulators; authenticated browsing/playback/download flows were not exercised.
- Signed iOS device builds and data-preserving installation passed after CoreStore embedding. Physical launch was then rejected by device `amfid` because the provisioning profile required online authorization (`0xe8008026`, `PPQCheck = true`). Refreshing provisioning and trying another network did not resolve it in that recorded session.
- The record does not establish whether that device authorization problem still exists today. Recheck before diagnosing a new launch issue as the same failure. Old `/private/tmp` logs may no longer exist.
- Authenticated UI/playback/download behavior, real-store migrations, background download callbacks, all four players' tracks/rates/zoom/PiP, and physical Apple TV Top Shelf/deep-link behavior remain unverified by this handoff. Later commits and current edits have not been build-validated during this task.

No new feature request or prioritized roadmap was supplied with this handoff. Continue from the next user request. If asked to stabilize the current tree, first review the uncommitted server-selection recovery and recent PiP/search/connection fixes, then choose validation relevant to the reported problem.

## Working rules for the next agent

1. Read `AGENTS.md`, check `git status --short`, and inspect relevant existing diffs before editing. Do not discard local signing settings or unrelated work.
2. Do not run builds by default. Historical build authorization is not standing authorization for a new task. If using XcodeBuildMCP, read the installed XcodeBuildMCP skill before calling its tools.
3. Preserve the platform UI and durable data contracts above. Trace routing/call sites before deleting a similarly named shared or platform implementation.
4. Keep checks proportionate. This handoff was prepared with source/history inspection and documentation checks only; no build, app launch, dependency update, or device change was needed.
5. Keep local credentials and developer signing configuration out of a publishable change. Use the existing configuration mechanism rather than silently rewriting the user's current settings.

For detailed historical integration reasoning, the retired notes remain readable without restoring them:

```sh
git show c64ca03d7:docs/rebase-main-preserve-ui.md
git show c64ca03d7:docs/rebase-resolution-record.json
```

The existing README and `Documentation/` files provide upstream background, but do not fully describe this fork. Current code and the explicitly dated integration evidence take precedence when those older documents differ.
