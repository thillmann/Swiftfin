# tvOS Series Detail Implementation Plan

## Source Plan

This implementation plan subdivides the work described in [`Documentation/plans/tvos-series-detail-plan.md`](tvos-series-detail-plan.md).

Treat the source plan as canonical for:

- visual direction and reference measurements
- target component names
- data and action boundaries
- episode timeline behavior
- focus preservation rules
- states and preview coverage

This document focuses on sequencing, review boundaries, and verification.

## Implementation Principles

- Keep the app buildable after every phase.
- Prefer small reviewable changes over one large rewrite.
- Preserve existing playback, routing, image, favorite, and Jellyfin API behavior unless the source plan explicitly replaces it.
- Do not remove the old selector until the new timeline can play episodes, open episode details, and preserve focus reliably.
- Build reusable scroll/focus mechanics separately from series-specific Jellyfin loading.
- Use the source plan's visual measurements as the design contract for polish.

## Phase 1: Series Detail Shell

Goal: create the new series-specific composition without taking on episode timeline complexity.

Source plan references:

- Proposed structure
- Design direction
- Reference measurements
- Motion and scroll-state behavior
- Hero

Tasks:

- Add `Swiftfin tvOS/Views/ItemView/Components/SeriesDetail/`.
- Add `SeriesDetailView`.
- Add a series-specific scroll container path, preferably `SeriesCinematicScrollView`, if the existing `CinematicScrollView` header slot is too constrained.
- Model scroll/focus progress for at least two visual states:
  - hero-focused, with episode rail teased and season pills hidden
  - content-focused, with blurred hero backdrop, centered logo, season pills, and lower content visible
- Treat the episode rail as the normal scroll anchor, then drive secondary parallax/fade effects from the rail's vertical progress.
- Introduce a small scroll choreography model, owned by the series scroll container, that exposes normalized progress for:
  - backdrop blur/dim
  - centered logo opacity and parallax offset
  - season pill opacity and locked position
  - lower content delayed offset
- Wire `ItemView.SeriesItemContentView` to `SeriesDetailView(viewModel:)`.
- Build a static shell with hero, temporary episode content placeholder, cast placeholder, and synopsis placeholder.
- Keep the existing `SeriesEpisodeSelector` available during this phase if needed for functional fallback.

Acceptance criteria:

- tvOS target builds.
- Series detail routes to the new shell.
- Moving focus down can drive the shell toward the content-focused visual state, even if the final timeline is still placeholder content.
- Episode rail movement is the source of truth for the transition; logo, pills, backdrop, and lower content derive from that progress.
- No playback or favorite behavior is removed.
- Existing non-series item detail pages remain unchanged.

Verification:

- Build the tvOS target.
- Open a series detail page in the simulator.
- Confirm the initial state teases the episode rail without showing season pills.
- Confirm focus-down produces a progressive transition rather than a hard opacity swap.
- Confirm movie, episode, and collection detail pages still use the existing detail layout.

## Phase 2: Hero, Favorite, and Synopsis

Goal: finish the top-level series presentation before changing episode paging.

Source plan references:

- Hero
- Favorite button behavior
- Synopsis band
- Display models
- Reference measurements
- Motion and scroll-state behavior

Tasks:

- Add `SeriesHeroView`.
- Add `SeriesFavoriteButton`.
- Add `SeriesSynopsisBandView`.
- Add `SeriesHeroDisplayModel` and `SeriesSynopsisDisplayModel` mapping near the `SeriesDetailView` boundary.
- Use series backdrop art with left and bottom gradients.
- Use logo art when available and polished text fallback when not.
- Add scroll progress-driven blur/darken treatment for the hero backdrop.
- Fade/slide the centered logo into the content-focused state with a slower upward parallax offset than the episode rail.
- Show metadata from available series and `playButtonItem` fields.
- Show next-up/resume/first-available episode context from `SeriesItemViewModel.playButtonItem`.
- Show optional starring line from first cast members.
- Wire favorite state from `viewModel.item.userData?.isFavorite`.
- Wire favorite toggle through `viewModel.send(.toggleIsFavorite)`.
- Use `viewModel.item.overview` for synopsis and route "More" to the existing overview route.

Acceptance criteria:

- Hero matches the source plan's cinematic direction.
- Hero-to-content transition feels like a parallax scroll rather than a hard jump.
- Favorite button has distinct focused/unfocused and favorite/not-favorite states.
- Synopsis does not require extra per-episode media stream fetching.
- Sparse metadata still renders cleanly.

Verification:

- Build the tvOS target.
- Manually test favoriting/unfavoriting.
- Test series with logo art and without logo art.
- Test series with sparse metadata and missing overview.

## Phase 3: Reusable Virtualized Horizontal Rail

Goal: implement reusable scroll/focus infrastructure before adding Jellyfin-specific timeline logic.

Source plan references:

- Proposed structure: reusable virtualized horizontal rail primitive
- Continuous episode timeline
- Focus preservation

Tasks:

- Add `Swiftfin tvOS/Components/VirtualizedRail/`.
- Add `VirtualizedHorizontalRail`.
- Add `VirtualizedHorizontalRailViewModel` only if the reusable layer needs shared state; otherwise keep the view generic and state-driven.
- Add a reusable focus identity type or protocol that can represent item ID plus region.
- Support stable item identity.
- Support appending and prepending items.
- Support lazy load triggers near the head and tail.
- Support programmatic scroll to stable item IDs.
- Support restoring focus after prepends.
- Support optional loading and error sentinel views at the head and tail.
- Validate behavior with simple fixture data before connecting real episodes.

Acceptance criteria:

- The rail is generic and not coupled to `BaseItemDto`, seasons, or episodes.
- Prepending items does not visibly jump the focused item.
- A caller can distinguish focus on separate regions within the same item.
- A caller can jump to a specific item ID.

Verification:

- Add previews or fixture-only test views for loaded, loading-head, loading-tail, error-head, error-tail, append, and prepend states.
- Build the tvOS target.
- Manually exercise focus and scroll behavior in previews or a temporary fixture host.

## Phase 4: Episode Card Visuals and Actions

Goal: build the new episode card treatment while preserving existing play/detail behavior.

Source plan references:

- Episode card
- Display models
- Focus preservation
- States to cover

Tasks:

- Add `SeriesEpisodeCardView`.
- Add `EpisodeCardDisplayModel` mapping near the timeline boundary.
- Implement landscape image, metadata overlay, progress, watched/resume/missing/unaired states.
- Implement two focus regions:
  - poster/play
  - content/details
- Route poster action to `.videoPlayer(item:queue:)` with `EpisodeMediaPlayerQueue(episode:)`.
- Route content action to `.item(item:)`.
- Use `SystemImageContentView` for image failure.
- Avoid depending on experimental changes to `SeriesEpisodeSelector.EpisodeCard`, `SeriesEpisodeSelector.EpisodePoster`, or `SeriesEpisodeSelector.EpisodeContent`.

Acceptance criteria:

- Poster focus and content focus are visually distinct.
- Poster select plays the episode.
- Content select opens episode detail.
- Missing and unaired episodes do not advertise playable behavior.
- Long titles and overviews do not break card layout.

Verification:

- Build the tvOS target.
- Preview or manually inspect watched, partially watched, unaired, missing, no-image, long-title, and long-overview states.
- Manually test playback and episode detail navigation.

## Phase 5: Series Episode Timeline View Model

Goal: create the Jellyfin-specific timeline model without season pill jumping yet.

Source plan references:

- Timeline view model
- Bidirectional loading strategy
- Backward paging caveat
- Lazy load triggers
- Focus preservation

Tasks:

- Add `SeriesEpisodeTimelineViewModel`.
- Track per-season paging state.
- Flatten loaded episodes into `SeriesEpisodeTimelineItem` values for the reusable rail.
- Initial anchor selection:
  - use `playButtonItem.seasonID`
  - fall back to first season
  - load first page
  - prefer `adjacentTo` around `playButtonItem.id` when the first page does not contain the anchor episode
  - fall back to capped paging if `adjacentTo` is unavailable
- Add forward lazy loading.
- Add backward lazy loading.
- Use response total count when available to compute previous-season final pages.
- Avoid eager full-season scans except as an explicit fallback.
- Preserve compound focus identity across data mutations.

Acceptance criteria:

- Initial focus starts near the current next-up/resume episode when available.
- Forward loading crosses season boundaries.
- Backward loading crosses season boundaries.
- Loading preserves focus and avoids visible jumps.
- Errors are isolated to the failed direction where possible.

Verification:

- Build the tvOS target.
- Test a series with multiple seasons.
- Test a series where `playButtonItem` is not in the first page.
- Test forward loading into the next season.
- Test backward loading into the previous season.
- Test retry behavior for page errors if implemented in this phase.

## Phase 6: Timeline View Integration

Goal: connect the reusable rail, episode card, and timeline view model into the detail page.

Source plan references:

- Continuous episode timeline
- Episode card
- Screen states
- Episode timeline states

Tasks:

- Add `SeriesEpisodeTimelineView`.
- Own `SeriesEpisodeTimelineViewModel` from `SeriesDetailView`.
- Render timeline items through `VirtualizedHorizontalRail`.
- Render loading, empty, and directional error states.
- Trigger timeline refresh when the series or seasons change.
- Replace the temporary episode placeholder or old selector with the new timeline once feature parity is met.

Acceptance criteria:

- The old selected-season episode selector is no longer shown on the new series detail page.
- Episodes render as one continuous rail across seasons.
- Playback and detail routes work from the new rail.
- Empty and loading states do not trap focus.

Verification:

- Build the tvOS target.
- Manually test focus entry from hero into timeline.
- Manually test focus exit from timeline back to hero or into lower content.
- Manually test playback route, then return to detail page.
- Manually test opening episode detail, then return to detail page.

## Phase 7: Season Pill Rail

Goal: add season navigation on top of the continuous timeline.

Source plan references:

- Season pills
- Continuous episode timeline
- Timeline view model
- Motion and scroll-state behavior

Tasks:

- Add `SeriesSeasonPillRail`.
- Add `SeasonPillDisplayModel` mapping.
- Select the initial season from `playButtonItem.seasonID` when available.
- Keep pill selection synchronized with the timeline's focused or visible season.
- Selecting a pill asks the timeline to jump to that season's first episode.
- If the target season is not loaded, load enough data to materialize the jump target.
- Show a loading target state while the jump is being prepared.
- Handle empty/unavailable seasons without breaking focus.
- Keep the pill rail hidden in the initial hero-focused state and fade it into a visually locked position above the episode rail as the episode rail scrolls up.

Acceptance criteria:

- Selecting a season jumps within the continuous rail rather than filtering the rail.
- Season pills appear as part of the hero-to-content transition, not as a static control over the initial hero.
- Season jump preserves stable focus.
- Many seasons remain horizontally navigable.
- One-season shows still render consistently unless design review decides otherwise.

Verification:

- Build the tvOS target.
- Test season jumps to loaded seasons.
- Test season jumps to unloaded seasons.
- Test season jump to empty or missing-only seasons if available.
- Test many-season and one-season shows.

## Phase 8: Cast Rail, Polish, and Previews

Goal: bring the page to final visual quality and cover important states.

Source plan references:

- Cast and crew
- SwiftUI previews
- States to cover
- Reference measurements

Tasks:

- Add `SeriesCastAndCrewRail` or style the existing `ItemView.CastAndCrewHStack` enough for the first release.
- Add `CastCreditDisplayModel` mapping.
- Tune hero gradients, logo sizing, rail positions, card scale, glass band, and focus states against the source plan's measurements.
- Add SwiftUI previews with in-code fixtures.
- Add preview artwork only if useful; do not assume a pre-existing preview asset.
- Validate accessibility labels for buttons, pills, and cards.
- Remove any temporary fallback selector code from the new series detail path.

Acceptance criteria:

- The page visually tracks the reference: cinematic hero, centered logo/pills in scrolled state, glassy rail area, and clear focus affordances.
- Important states from the source plan have preview or manual coverage.
- No new dense metadata section is introduced.
- Old series selector code remains only if used elsewhere or intentionally retained as dead-code-free reference is not required.

Verification:

- Build the tvOS target.
- Run on tvOS simulator.
- Manually test:
  - initial loading
  - background refresh
  - missing backdrop
  - missing logo
  - favorite toggle
  - next-up/resume/first-available hero context
  - season pill focus and jump
  - episode rail scroll-up drives pill fade-in, logo parallax, backdrop blur, and delayed lower-content movement
  - focus-up reverses the choreography cleanly
  - bidirectional lazy loading
  - focus preservation after prepend
  - playback routing
  - episode detail routing
  - cast focus
  - synopsis "More" route

## Recommended PR Breakdown

1. Series detail shell and series-specific scroll container.
2. Hero, favorite button, and synopsis band.
3. Reusable virtualized horizontal rail.
4. Episode card visuals and actions.
5. Episode timeline view model.
6. Timeline integration.
7. Season pill rail.
8. Cast rail, visual polish, previews, and simulator QA.

## Risks And Mitigations

- Scroll and focus behavior may be harder with `CollectionHStack` when prepending.
  Mitigation: isolate the behavior in `VirtualizedHorizontalRail` and switch implementation internals without changing the series timeline API.

- Anchor loading may require too many episode fetches if `adjacentTo` is unavailable or unsuitable.
  Mitigation: prefer `adjacentTo`, cap fallback scans, and fall back to the first loaded episode rather than blocking the page.

- Season jumps to unloaded seasons can create visible jumps.
  Mitigation: show a loading target pill state, materialize the target episode first, then scroll to the stable ID.

- Hero layout could conflict with unpredictable backdrop art.
  Mitigation: use strong left and bottom gradients, constrain hero copy width, and verify against multiple real series.

- The reusable rail could grow too generic too soon.
  Mitigation: build only the mechanics needed by this timeline first, but keep DTOs and series concepts out of the reusable layer.
