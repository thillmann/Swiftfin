# UI-preserving origin/main migration

## Starting checkpoint

- Source: `codex/tvos-liquid-glass`, `3043dbbae7d7e4b8dc6d7b691980767fa1ba472d` (latest local HEAD, clean working tree).
- Upstream: local `origin/main`, `2229d6f616993dc65d8137855676a9bb3521e64a`.
- Merge base: `b6fe22a8f2e96ce26c2d489dbf411d4b8b3ff9fb`.
- Backup: `codex/backup-tvos-liquid-glass-20261012`; source branch is unchanged.
- Integration: `codex/rebase-main-preserve-ui`; worktree `/private/tmp/swiftfin-rebase-main-preserve-ui`.
- Rebase the cumulative final source tree as one commit (198 source commits remain in source/backup history). This avoids resolving transient intermediate designs against the final upstream architecture.
- No fetch, build, push, or force-push requested/performed. Use recorded local upstream.

## Migration checklist

Checked items mean code integration and source inspection are complete; device behavior still needs the runtime validation listed below.

- [x] iOS/iPadOS: preserve `Swiftfin/Views/HomeView` cinematic carousel/backdrop, Next Up playback, fade/loading behavior, tab navigation/search activation and keyboard dismissal; `SearchView` genres, unified results and iPad search; `ItemView` phone/iPad cinematic/compact layouts, action sheets, metadata wrapping, episode details/rails/selection/queue navigation; platform `PosterButton` gestures/previews, glass and fallback/loading appearance; lazy `PosterVGrid`, paging libraries, genre intersection filtering and bottom insets. Evidence: source commits `15c53fb58`, `1c5dee5b5`, `3437ac2ac`, `031f58b7e`, `204511cbf`, `71898eb81`, `796836e4f` and final source files.
- [x] tvOS: preserve cinematic home and reusable `CinematicItemHeroView`, animated background/fallback/logo trimming, hero play targets and favorite state, recently-added presentation, retained scroll position; `FeatureButton`, shared base poster customization/circular posters/lazy grids/indicators; season pills and episode focus/identity/scroll restoration; restored playback controls and supplements; Top Shelf extension/cache/deep links/app group. Evidence: `409a5c0dc`, `743d5f651`, `f05cd3645`, `f5065dd8c`, `92f4360e2`, `fd4ce6345`, `896f65b18` and final platform files.
- [x] Discovery: Seerr settings/client/request flow, result overlays/matching, genre discovery and ALL-selected genre filtering, studio/network rails, upcoming media/new episode dates, unified search. Evidence: `48dec8477`, `9b62cf539`, `29cabc6e4`, `c728ea688`, `097872b63`, `f563981b5`, `dd34f2b16` and `Shared/Services/Seerr*`, `GenreMediaSource`, `UnifiedMediaResult`.
- [x] Downloads: preserve durable `DownloadRecord` Codable format/identity/status/progress, manager storage paths and recovery, iOS-only download UI, offline launch/browsing/playback and progress reconciliation, downloaded-media preference, cancellation cleanup, automatic/exact source selection and refreshed-source recovery. Evidence: `63397688a`, `731ae3e99`, `78503a7ba`, `0c591a155`, `f483516d9`, final manager/record/source-selection/offline files. Never discard stored records or reset settings.
- [x] Playback: retain Aether alongside upstream AVPlayer/VLC/MPV; adapt Double rates, layout/capability protocols, lifecycle and tracks; preserve Aether profiles/sidecars/PiP/rate-after-play-and-seek and clock throttling. Adopt upstream state/layout/zoom, subtitle fixes, reporting/transcode cleanup and Live TV stream/track fixes. Preserve source `115fbf8d4` crash fix and `3043dbbae` simulator fix. Evidence: `78fd05cad`, `8c0b63b6d`, source proxies/build/manager, upstream `dbe6140d2`, `667addf0a`, `ffe5282c8`, `83ab4365d`, `2229d6f61`.
- [x] Startup/persistence/project: preserve appearance/network/startup diagnostics, persistent stores/default keys, offline user selection; integrate upstream shared ItemStore and SDK/data changes; reconcile target memberships, schemes, Top Shelf app group/extension, Aether package with upstream pinned dependencies, deployment targets, generated localization replacement. Evidence: `bf880e53c`, `1bc90ec7a`, `8e8747e5e`, upstream `06176bd58`, `88cbbbdfe`, `800d1085f`, `90fe3d8b4`.

## Replacement trace and conflict decisions

- Upstream deletes iOS HomeView/SearchView/PagingLibraryView and consolidates shared LibraryView/Home content; inspect replacements before choosing platform versions. Relocation is not redundancy.
- Upstream shared `ItemView` uses `ContentGroup`, `ItemStore` and header groups; source platform cinematic layouts remain required. Adapt data/actions while retaining visual implementations.
- Upstream removes downloads; source manager, durable records and iOS download views remain required.
- Upstream `VideoPlayerType.avPlayer` retains raw value `native`; migration of prior `swiftfin` selection must select VLC, while `aether` remains stable.
- The platform implementations remain the default home, detail, search and library routes. They use `PlatformItemView`, `PlatformPoster`, `PlatformPosterButton`, `PlatformPosterImage`, `PlatformPagingLibraryView` and `PlatformSearchView` to coexist with upstream shared views. Customized geometry, animations, focus identities, loading placeholders, gestures, episode rails and source selection remain in their source files.
- Shared `UserSession`/`ItemStore` requests and serialized user-data mutations feed platform snapshot notifications. Legacy library models retain shared records and replace matching snapshots without rebuilding their collections. Store deletion notifications remove items. Offline providers and playback items retain their local metadata independently of server-store invalidation.
- Aether implements upstream `VideoMediaPlayerLayoutConfigurable` and iOS `MediaPlayerPictureInPictureCapable`. The renderer uses viewport scale/offset while subtitle overlays retain viewport size. Load respects the manager's playing/paused state; desired rate survives play, seeks and track reloads. Actual Aether audio/embedded/sidecar track IDs populate `MediaTrackIndexMap` after probing. VLC/AVPlayer/MPV use upstream track and lifecycle implementations.
- Online playback retains source source-catalogue hydration, explicit-version recovery, timeout retry, profile-free PlaybackInfo recovery, authenticated/remote URLs and HLS MPEG-TS fallback. Upstream Live TV program-to-channel resolution, placeholder-source handling, stream tags/liveStreamID, playback overrides and store checks are integrated. Offline bitrate/version controls are suppressed; local track switching and progress persistence remain.
- Source download manager, task, durable record and local storage code remain. `DownloadRecord`'s Codable schema and storage-path implementation are byte-for-byte unchanged apart from an added non-persisted backend-selection helper. AVPlayer selections fall back to VLC for downloaded unsupported containers or subtitle sidecars, without changing the stored preference.
- Existing `itemViewType` remains the source compact/cinematic preference under `platformItemViewType`; upstream media-item preferences use a separate key. Native/Swiftfin persisted backend names decode as AVPlayer/VLC; Aether remains `aether`. Legacy poster/library/subtitle keys and per-library StoredValues remain. Existing global settings migrate once into upstream grouped settings only when the destination is absent. Advanced shared customization remains available alongside source controls.
- Project retains upstream iOS 18.6/tvOS 26.1 deployment requirements, SDK 3.3, FactoryKit, SwiftVLC, MPV and accessibility packages, plus Aether 6.6.0 and the Top Shelf extension. CoreStore is pinned to source revision `4cf205a57b57eda24d88571a9aee4023b5c3981b` to retain the Xcode 27 fix. Duplicate package products/link entries and invalid package bindings were reconciled. Top Shelf target dependency, app-extension embed phase, app group, generic TVServices framework path, source memberships and shared schemes were checked.
- English localization is the union of upstream and source keys, including legacy UI keys, and `Shared/Strings/Strings.swift` was regenerated with upstream's generator. Other upstream localizations remain; untranslated source strings fall back to English.

## Consolidations and redundancy evidence

No branch feature was deliberately removed. These old implementations were consolidated only after tracing their replacements:

| Source change/file | Retained equivalent or adaptation |
| --- | --- |
| `MediaTrackIndexMap` nil `IsExternal` fix | Upstream map explicitly uses `isExternal != true` for embedded tracks. Fixture checks cover omitted flags, multiple audio tracks and transcoding. Aether has a separate probed-ID mapping. |
| Source Transmission crash upgrade (`115fbf8d4`) | Upstream pins the same Transmission 2.13.4 release. Source `3043dbbae` compiler-conditional hosting initializer remains in restored UI, while the new upstream host uses the current initializer. |
| `VideoPlayerType+Swiftfin.swift` | Renamed upstream VLC profile file retains source HLS MPEG-TS fallback and source profile options; Aether retains its own profile. Persisted `swiftfin` maps to VLC. |
| `RootItem`/`ServerCheckView` startup plumbing | `RootView` → `UserSessionRootView` → cached `UserSessionManager` startup replaces the old root/server-check states. Download preparation and non-blocking metadata refresh are integrated, preserving offline entry without an online gate. |
| Old player/supplement container controllers | Upstream `Container`, `ViewState` and supplement host provide layout/zoom/lifecycle handling. Source 55%-height cinematic fade, glass supplement tabs, rail sizing, episode/chapter content, full episode/program titles, live badge, loading/buffering overlay and Skip Intro are ported into them. |
| `VideoPlayerSlider` | Upstream `SliderContainer`/`CapsuleSliderStyle` carries committed/origin progress, scrubbing, focus and chapter masking. Source Live TV program timeline remains non-seekable with start/end times and unfocused progress visible. |
| tvOS `CapsuleSlider`, `PlaybackRateMediaPlayerSupplement` | `git grep` at the recorded source finds only their definitions (no call sites); they had no deployed interaction. Upstream rate menu preserves preset rates and adds `PlaybackAdjustmentSupplement` for custom rate, audio/subtitle offsets. |
| Source SelectUser bottom bar | Upstream `SelectUserView+Toolbar` retains its server/add/select/delete actions and source glass/destructive styles. |
| Source duplicate tvOS `ListRow` | Upstream shared `ListRow` supports the same content/action layout and clipping, with accessibility improvements; the duplicate declaration was removed. |
| Admin user error wrapping | Upstream Stateful model retains the original thrown `Error`, replacing the older localized-description-only state. Source structured network errors remain in `ErrorMessage`/`ErrorView`. |

## Validation and remaining work

Passed without an app build:

- Swift parse-only checks for 897 iOS/iPadOS and 811 tvOS source files, plus the Top Shelf source, with their platform conditional compilation targets.
- Standalone fixtures using the actual backend decoding initializer and track-map implementation: native/Swiftfin/Aether/MPV/VLC persisted values, omitted `IsExternal`, direct-play and transcoded audio mappings.
- Project object graph has no dangling object references; both app targets include Aether and upstream requirements; Top Shelf target dependency and app-extension embed phase are present. Schemes parse as XML; combined package pins, plist/entitlement files and JSON assets parse.
- All 109 source-added files remain. DownloadRecord persistent schema/storage paths match the starting source. Every current L10n reference has a definition. Localization generator completed successfully.
- Conflict-marker and whitespace checks; source and backup refs verified unchanged; upstream ancestry and clean integration worktree checked after rebase completion.

Not performed: app build/type checking, dependency resolution on a fresh checkout, simulator/device execution, UI screenshots or interaction tests. These are material remaining risks: three-platform layouts/navigation/animation/focus restoration, migrated real user stores and existing download packages, background download callbacks, all four players' playback/tracks/rates/zoom, Aether software/native PiP, Live TV/session reporting, and signed Top Shelf installation/deep links. Syntax and source inspection do not establish runtime equivalence. No push or force-push.
