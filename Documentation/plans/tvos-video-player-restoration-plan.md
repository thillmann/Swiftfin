# tvOS Video Player Restoration Plan

## Goal

Bring the tvOS video player back to full remote-driven functionality while preserving the newer shared media player architecture introduced by `Media Player (#1581)`.

The target is not to resurrect the deleted tvOS player implementation. The target is to restore the behavior that users expect from a tvOS player:

- playback starts reliably through the shared `MediaPlayerManager`
- the Siri Remote can show, hide, and navigate controls
- menu/back follows a staged dismissal flow instead of immediately exiting playback
- play/pause, seek, audio, subtitles, aspect fill, autoplay, next/previous, and playback speed are functional
- supplements such as info, chapters, queue, people, and playback information are discoverable and useful on tvOS
- focus movement is predictable and does not leave the user in blank or inert controls

## Background

The current player surface came from commit `7925b6e7` on 2025-09-19, authored by Ethan Pippin:

```text
Media Player (#1581)
```

That commit replaced the old platform-specific player trees with a shared playback model:

- `Shared/Components/VideoPlayer.swift`
- `Shared/Objects/MediaPlayerManager/`
- `Shared/Objects/VideoPlayerContainerState.swift`
- `Swiftfin tvOS/Views/VideoPlayerContainerState/PlaybackControls/`
- `Swiftfin/Views/VideoPlayerContainerView/`

The iOS side received the more complete version of the new interaction model:

- tap toggles the overlay
- pan reveals supplements
- supplement tabs switch content
- playback speed and gesture lock are implemented
- overlay visibility is driven by `VideoPlayerContainerState`

The tvOS side received a thinner parallel implementation:

- a basic `UIPress` bridge
- hard-coded supplement geometry
- incomplete overlay visibility handling
- supplement title buttons with empty actions
- configured action buttons that can render `EmptyView()`
- blank tvOS supplement bodies for default supplements

Later commits layered more shared functionality on top:

- `cbb518ac` on 2026-04-23, `Playback Info (#1941)`, improved playback information and polished the iOS supplement title strip.
- `0c7ee389` on 2026-04-28, `Supplement Customization, People Supplement, & VLCKit 3.7.2 (#1984)`, made supplements configurable and added People.
- `3ed9163c` on 2026-05-18, `Disable Conflicting Player Gestures (#2016)`, adjusted shared/iOS gesture dismissal behavior.

These commits did not finish the tvOS overlay interaction model.

## Current Relevant Code

Primary tvOS files:

- `Swiftfin tvOS/Views/VideoPlayerContainerState/PlaybackControls/PlaybackControls.swift`
- `Swiftfin tvOS/Views/VideoPlayerContainerState/PlaybackControls/VideoPlayerContainerView.swift`
- `Swiftfin tvOS/Views/VideoPlayerContainerState/PlaybackControls/SupplementContainerView.swift`
- `Swiftfin tvOS/Views/VideoPlayerContainerState/PlaybackControls/Components/PlaybackProgress.swift`
- `Swiftfin tvOS/Views/VideoPlayerContainerState/PlaybackControls/Components/NavigationBar.swift`
- `Swiftfin tvOS/Views/VideoPlayerContainerState/PlaybackControls/Components/ActionButtons/`

Shared files:

- `Shared/Components/VideoPlayer.swift`
- `Shared/Objects/VideoPlayerContainerState.swift`
- `Shared/Objects/VideoPlayerActionButton.swift`
- `Shared/Objects/VideoPlayerSupplement.swift`
- `Shared/Objects/MediaPlayerManager/MediaPlayerManager.swift`
- `Shared/Objects/MediaPlayerManager/Supplements/`
- `Shared/Objects/MediaPlayerManager/MediaPlayerProxy/`

Old behavior reference:

- commit before `7925b6e7`
- deleted path `Swiftfin tvOS/Views/VideoPlayer/`
- especially `Overlays/Overlay.swift`, `Overlays/Components/BottomBarView.swift`, and `Overlays/SmallMenuOverlay.swift`

Use the old files as a behavioral reference, not as code to copy wholesale.

## Non-Goals

- Do not redesign the entire player visually before restoring core behavior.
- Do not replace `MediaPlayerManager` or return to the old `VideoPlayerManager`.
- Do not make iOS player changes unless a shared type must be clarified for tvOS.
- Do not run builds by default; follow the repo instruction and verify through review unless an implementation phase explicitly calls for build verification.

## Proposed State Model

Clarify tvOS overlay behavior around a small explicit state model.

Initial conceptual states:

```swift
enum TVVideoOverlayMode: Equatable {
    case hidden
    case controls
    case scrubbing
    case supplement
    case confirmClose
}
```

Map this model onto existing state during implementation:

- `hidden`: `isPresentingOverlay == false`
- `controls`: `isPresentingOverlay == true`, `isPresentingSupplement == false`, `isScrubbing == false`
- `scrubbing`: `isScrubbing == true`
- `supplement`: `isPresentingSupplement == true`
- `confirmClose`: new or restored close-confirm state

The model should clarify, or eventually replace, ambiguous meanings of:

- `isPresentingOverlay`
- `isPresentingPlaybackControls`
- `isPresentingSupplement`
- `isScrubbing`
- `presentationControllerShouldDismiss`

## Remote Input Contract

When overlay is hidden:

- select or directional press shows controls
- play/pause toggles playback and may show brief feedback
- menu/back presents close confirmation rather than immediately stopping playback

When controls are visible:

- select activates the focused control
- directional focus moves between progress, action buttons, supplement tabs, and content
- play/pause toggles playback
- menu/back hides controls or enters close confirmation
- idle timer hides controls only when not paused, not scrubbing, not in a menu, and not in a supplement

When supplement is visible:

- left/right or focus movement changes supplement tabs
- select activates focused supplement content
- menu/back closes the supplement first
- controls should not disappear while supplement content is active

When confirm-close is visible:

- second menu/back exits playback
- select may confirm if the UI exposes a confirmation action
- timeout returns to playback controls or hidden playback, depending on the chosen design

## Implementation Sequence

## Phase 1: Restore Overlay and Remote State

Goal: make the player controllable with the Siri Remote again.

Tasks:

- Introduce a tvOS-focused overlay mode, either as a local helper or as a narrow addition to `VideoPlayerContainerState`.
- Make select and directional press show the overlay when hidden.
- Replace immediate menu dismissal in `PlaybackControls` with staged behavior:
  - close supplement if one is open
  - hide controls or show confirm-close
  - exit playback only after confirmation
- Reconnect the overlay timer so it hides controls only in valid states.
- Re-enable visibility gates for navigation and progress controls.
- Keep play/pause wired through `MediaPlayerManager.togglePlayPause()`.
- Add visible feedback for play and pause when controls are hidden.

Acceptance criteria:

- Playback does not exit on the first accidental menu/back press during normal playback.
- Controls can be shown and hidden by remote input.
- Controls auto-hide during playback.
- Controls stay visible while paused, focused, scrubbing, or in a supplement.
- The shared manager/proxy lifecycle remains unchanged.

Verification:

- Code review remote state transitions.
- Manually verify on tvOS simulator or device when implementation begins.

## Phase 2: Repair Action Buttons

Goal: ensure configured/default controls never render inert UI.

Tasks:

- Audit every `VideoPlayerActionButton` case.
- Implement tvOS playback speed controls, likely using the existing `manager.rate` and `manager.set(rate:)` path.
- Implement tvOS gesture lock only if it has meaningful tvOS behavior; otherwise remove it from tvOS presentation.
- Ensure defaults do not include buttons that render `EmptyView()`.
- Verify audio and subtitle menus update `MediaPlayerItem` selected stream indexes and proxy tracks.
- Verify aspect fill, autoplay, next item, and previous item behavior.
- Reconsider whether menu buttons should remain SwiftUI `Menu` controls or become focus-native rows/buttons for tvOS.

Acceptance criteria:

- No default action button maps to `EmptyView()`.
- User-customized button lists degrade safely if they contain unsupported actions.
- Audio/subtitle/playback-speed controls are visible only when applicable.
- Live streams hide unsupported controls.

Verification:

- Static review of `ActionButtons.filteredActionButtons`.
- Manual verification with movie, episode queue, and live stream items.

## Phase 3: Restore Seek and Progress Behavior

Goal: make progress display and seeking complete on tvOS.

Tasks:

- Define directional press behavior for progress:
  - if progress is focused, left/right scrubs
  - if overlay is hidden, left/right may show controls first
  - optional: repeated left/right outside the progress control performs fixed jump
- Ensure `containerState.scrubbedSeconds` updates while scrubbing.
- Commit scrubbed position through `proxy.setSeconds(...)` once editing ends.
- Keep progress display in sync with `manager.seconds`.
- Handle zero or missing runtime defensively.
- Keep live streams in a non-seekable live indicator state.

Acceptance criteria:

- Scrubbing does not seek on every tiny focus movement unless intentionally designed.
- Scrubbing commits to the selected timestamp.
- Runtime-less and live items do not expose broken progress controls.
- The timestamp labels never show invalid values.

Verification:

- Manual verification with normal VOD, resume item, near-end item, and live stream.

## Phase 4: Repair Supplement Navigation

Goal: make supplements discoverable and navigable with focus.

Tasks:

- Replace empty supplement title button actions with `containerState.select(supplement:)`.
- Keep `focusedSupplementID` and `selectedSupplement` synchronized without feedback loops.
- Add clear selected styling distinct from focus styling.
- Decide the tvOS supplement model:
  - simple focused tab switches content below, or
  - page-style supplement switching adapted from iOS
- Ensure menu/back closes supplement mode before exiting playback.
- Ensure focus can move from title tabs into content and back.
- Remove placeholder styling such as `Color.blue.opacity(0.2)`.

Acceptance criteria:

- Every visible supplement title can be selected.
- Selected supplement content appears reliably.
- Focus does not get trapped in tabs or content.
- Supplement state survives temporary focus movement inside the supplement.

Verification:

- Manual verification with all configured supplements.

## Phase 5: Implement Missing tvOS Supplements

Goal: remove blank default panels.

Tasks:

- Implement `MediaInfoSupplement.tvOSView`.
- Implement `MediaChaptersSupplement.tvOSView`.
- Verify `EpisodeMediaPlayerQueue` tvOS layout and actions.
- Verify `MediaPeopleSupplement.tvOSView`.
- Verify `PlaybackInformationSupplement.tvOSView`.
- Filter unsupported supplements per platform until implemented.
- Keep supplement bodies focused on playback context; avoid deep navigation unless an existing pattern already supports it.

Acceptance criteria:

- Default supported supplements do not show blank content on tvOS.
- Info shows title, metadata, overview, and from-beginning action when applicable.
- Chapters show focusable chapter cards or rows and seek on selection.
- Queue supports next/previous episode selection.
- People and playback information render without breaking focus.

Verification:

- Manual verification with:
  - movie with chapters
  - episode with queue
  - item with people
  - transcoding playback information
  - direct play playback information

## Phase 6: Layout and Focus Polish

Goal: make the restored player feel like a finished tvOS surface.

Tasks:

- Replace hard-coded supplement offsets such as `500` and `100` with responsive layout derived from screen height and safe areas.
- Respect `safeAreaInsets` consistently.
- Remove unused state and debug modifiers:
  - unused `contentSize`
  - unused `effectiveSafeArea`
  - `.debugBackground()`
  - dead empty change handlers
- Build explicit focus paths between:
  - progress
  - title/action row
  - supplement tabs
  - supplement content
- Audit typography and spacing for long titles, subtitles, and stream names.
- Ensure the player overlay does not visibly jump when focus changes.

Acceptance criteria:

- Overlay layout works on common tvOS resolutions.
- Long labels do not overlap action buttons.
- Focus movement is predictable in every visible overlay mode.
- No placeholder/debug styling remains.

Verification:

- Manual simulator/device pass.
- Screenshot review if simulator is available.

## Phase 7: Regression and Manual Verification

Goal: verify full player behavior across common playback paths.

Scenarios:

- movie playback from item detail
- episode playback with queue and autoplay
- resume playback from home rows
- search result playback
- trailer playback if routed through the same manager
- live stream playback
- item with no chapters
- item with no subtitles
- item with multiple audio tracks
- direct play
- transcoding
- near-end playback with next item
- playback error state

Checklist:

- playback starts
- overlay shows and hides
- play/pause works
- menu/back is staged
- seeking works
- audio and subtitle switching work
- aspect fill works
- autoplay toggle works
- next/previous work
- playback speed works or is hidden
- supplements open and close
- progress reporting still sends start/progress/stop
- route dismissal still resets the media player manager

## Testing Strategy

Prefer targeted tests for state and filtering logic where possible.

Candidate tests:

- overlay mode transitions from remote actions
- `presentationControllerShouldDismiss` behavior for hidden, controls, supplement, and confirm-close modes
- action button filtering for live streams, no queue, no audio, no subtitles
- supplement availability for item shapes

Avoid broad UI tests until the overlay state model is stable.

## Suggested Milestones

Milestone 1:

- restore overlay visibility
- restore staged menu/back behavior
- preserve play/pause

Milestone 2:

- remove blank default action buttons
- implement playback speed or hide it on tvOS
- verify audio/subtitle/aspect/next/previous/autoplay

Milestone 3:

- make supplement tabs selectable
- implement Info and Chapters tvOS bodies
- filter unsupported supplements

Milestone 4:

- responsive supplement layout
- focus polish
- full manual verification matrix

## Open Questions

- Should tvOS use a two-step menu close confirmation like the old player, or a visible confirm overlay with explicit buttons?
- Should left/right remote presses jump by fixed intervals when the progress bar is not focused?
- Should playback speed be a menu action, a supplement, or a compact focus-native selector?
- Should `VideoPlayerContainerState` remain shared across platforms, or should tvOS own a small adapter state to avoid coupling to iOS gesture concepts?
- Should default supplements be platform-specific until every supplement has a real tvOS body?
