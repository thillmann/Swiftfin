# tvOS Focus-Aware Hero Snap Collapse Plan

## Goal

Make the tvOS item detail hero behave like a deliberate focus-driven mode transition:

- Hero-focused state shows the full-screen hero with the next section teased at the bottom.
- Moving focus from the hero into primary content collapses the hero completely in one smooth transition.
- The collapsed state fades in top chrome, such as a logo, compact actions, tabs, filters, or section controls, while reserving stable space above the primary content.
- Moving focus within the primary content area does not trigger vertical scroll corrections.
- Moving focus back to the hero reverses the transition predictably.
- Moving focus farther down the page releases vertical scrolling back to the native tvOS focus engine.

This plan covers the shared scroll/focus choreography for any tvOS detail page that uses a full-screen cinematic hero. The series detail plans contain one concrete consumer of this behavior, but the architecture should work for movies, episodes, collections, people, artists, and future hero-based item views.

## Best-Practice Frame

Use a small state machine around region transitions instead of reacting to every focus change.

Apple's tvOS focus model works best when the app guides large structural transitions and lets the focus engine own steady-state navigation. In SwiftUI terms, the preferred tools are:

- `@FocusState` and `.focused(...)` for local focus ownership.
- `.focusSection()` for grouping related focusable controls.
- Programmatic scroll only for explicit boundary transitions.
- Native scroll behavior after the transition has settled.

The existing code already follows part of this model:

- `CinematicScrollView` owns the vertical scroll container.
- `collapsesSeriesHero` currently represents expanded vs collapsed hero layout for series pages only.
- `FocusGuide` tags identify the header and selected content regions in the current implementation.
- Existing horizontal rows, such as season and episode rows, already own their own horizontal focus and scroll behavior.

The main implementation work is to make the vertical choreography exact, one-way, and region-based.

## Current Relevant Code

Primary files:

- `Swiftfin tvOS/Views/ItemView/ScrollViews/CinematicScrollView.swift`
- `Swiftfin tvOS/Objects/FocusGuide.swift`
- `Swiftfin tvOS/Views/ItemView/ItemView.swift`
- `Swiftfin tvOS/Views/ItemView/SimpleItemContentView.swift`
- `Swiftfin tvOS/Views/ItemView/MovieItemContentView.swift`
- `Swiftfin tvOS/Views/ItemView/SeriesItemContentView.swift`
- `Swiftfin tvOS/Views/ItemView/CollectionItemContentView.swift`
- `Swiftfin tvOS/Views/ItemView/Components/EpisodeSelector/Components/HStacks/SeasonHStack.swift`
- `Swiftfin tvOS/Views/ItemView/Components/EpisodeSelector/Components/HStacks/EpisodeHStack.swift`

Current behavior to preserve:

- All item detail pages that use `CinematicScrollView` continue using the existing cinematic header behavior.
- Existing primary content rows keep their own horizontal focus and scroll handling.
- Type-specific preferred content anchors remain owned by each content view or view model. For example, `SeriesItemViewModel.playButtonItem` can still anchor initial episode focus.
- Existing playback, item routing, image loading, favorite actions, and Jellyfin API behavior are unchanged.

Current behavior to tighten:

- Collapse is currently implemented by shrinking and offsetting the header layout when `viewModel.item.type == .series && collapsesSeriesHero`.
- The current behavior is series-only. The new behavior should be shared by any item detail page that uses the cinematic hero.
- The current boolean state only models expanded vs collapsed. The final behavior needs an explicit native-content mode where vertical scrolling is no longer corrected by the hero transition logic.
- Collapsed top chrome needs to be represented explicitly instead of being implied by the header disappearing.

## Proposed State Model

Replace or wrap the current `collapsesSeriesHero` boolean with a richer mode model:

```swift
private enum CinematicFocusMode: Equatable {
    case hero
    case primaryContent
    case nativeContent
}
```

Meaning:

- `hero`: the app owns the scroll position at the top of the page. The hero is fully visible and primary content is only teased.
- `primaryContent`: the app owns the one-time snap to the collapsed boundary. The hero is fully out of view, top chrome is visible, and primary content can move horizontally or internally without vertical correction.
- `nativeContent`: the app stops correcting vertical offset. The focus engine and scroll view handle deeper page movement normally.

The mode should be the single source of truth for hero visibility, collapsed chrome visibility, and whether the app is allowed to correct the vertical content position.

## Focus Regions

Introduce explicit region classification near `CinematicScrollView`:

```swift
private enum CinematicFocusRegion {
    case hero
    case primaryContent
    case nativeContent
    case unknown
}
```

Initial mapping can use the existing focus guide tags:

- `headerTag` -> `.hero`
- `belowHeaderTag` -> `.primaryContent`
- `episodesTag` -> `.primaryContent`
- equivalent first-content tags for movie, episode, collection, person, and artist pages -> `.primaryContent`
- lower rows, once tagged -> `.nativeContent`
- missing tag -> `.unknown`

The important rule is that only region boundary changes may issue vertical scroll commands:

- `.hero` to `.primaryContent`: snap collapse once.
- `.primaryContent` to `.hero`: expand once.
- `.primaryContent` to `.nativeContent`: release native scrolling.
- `.nativeContent` to `.primaryContent`: do not force a snap unless the focused view is no longer visible or design review explicitly wants recentering.
- `.primaryContent` to `.primaryContent`: no vertical scroll.

## Layout Choreography

Hero state:

- `CinematicHeaderView` fills the viewport minus the existing tease amount.
- Primary content is visible only as a bottom tease.
- Collapsed top chrome opacity is zero and should not take focus.

Primary content state:

- The effective content position is settled at the collapsed boundary once.
- Hero is fully above the viewport.
- A top overlay fades in with compact hero chrome, such as logo/title, actions, tabs, filters, or section controls.
- The scroll content reserves matching top space so primary content does not sit underneath the overlay.
- Backdrop blur/dim derives from scroll progress or mode progress.

Native content state:

- Overlay can remain visible or transition out based on design polish, but vertical scroll position is not continuously corrected.
- Lower rows scroll normally with tvOS focus movement.

Returning to hero:

- Focus transition from primary content to hero sets mode to `hero`.
- Overlay fades out.
- The effective content position animates back to the hero state.
- Hero buttons regain focus using the existing header focus behavior.

## Implementation Sequence

## Step 1: Name the Regions and Modes

Goal: make the existing behavior easier to reason about without changing visuals.

Tasks:

- Add a local focus mode enum in `CinematicScrollView`.
- Add a local focus region enum in `CinematicScrollView`.
- Add a helper that maps existing focus guide tags to focus regions.
- Keep the existing `collapsesSeriesHero` boolean temporarily only if it is derived from the new mode and helps reduce churn.
- Route existing focus-target update logic through the new region helper.
- Preserve current behavior for every item type while the region model is introduced.

Acceptance criteria:

- Hero-to-content focus transitions still expand and collapse as before.
- Intra-content focus changes do not issue repeated vertical scroll requests once already collapsed.
- No new visual elements are introduced in this step.

Verification:

- Code review the region mapping against `headerTag`, `belowHeaderTag`, `episodesTag`, and any new item-type-specific primary content tags.
- Do not run a build for this step unless paired with larger code changes.

## Step 2: Convert Layout Collapse Into an Exact Boundary Settle

Goal: collapse the hero fully and predictably when focus enters primary content.

Tasks:

- Define the collapsed boundary as the visual state where the hero is fully out of view and primary content starts below any reserved collapsed chrome.
- Replace the current series-only layout collapse with mode-driven boundary settling that applies to all cinematic item types.
- Decide whether the implementation should use SwiftUI scroll APIs available to the deployment target or a narrow `UIScrollView` bridge. Prefer SwiftUI-native APIs if they can express the exact boundary reliably.
- If a `UIScrollView` bridge is required, isolate it inside `CinematicScrollView` and do not leak UIKit scrolling details into item content views.
- Keep expansion targeting the original hero state.
- Make the transition idempotent: while the hero-to-content transition is in flight, repeated focus updates should not restart or fight the animation.

Acceptance criteria:

- Moving focus down from hero settles to the same collapsed boundary every time.
- The hero is fully out of viewport after the transition, not partially visible.
- Horizontal or internal movement within primary content does not adjust the vertical content position.
- Moving back to hero returns to the original full-hero presentation.

Verification:

- Manually inspect the boundary calculation against `expandedHeaderHeight`, the hero tease amount, and the reserved collapsed chrome height.
- Simulator verification is recommended once this step is implemented because the behavior is motion-sensitive.

## Step 3: Add Collapsed Top Chrome

Goal: show compact hero chrome as part of the collapsed content mode.

Tasks:

- Add a top overlay inside the `CinematicScrollView` `ZStack` for collapsed chrome.
- Start with shared logo/title treatment and optional controls supplied by the active item content.
- Drive overlay opacity from `CinematicFocusMode.primaryContent` or from normalized scroll progress if the visual needs to track the animation more closely.
- Disable hit testing or focus participation while the overlay is hidden.
- Add a matching spacer or reserved inset in the scroll content when primary content is collapsed.
- Keep primary content below the reserved top area.

Acceptance criteria:

- The collapsed state shows compact hero chrome at the top of the viewport.
- Primary content does not jump or render underneath the overlay.
- The overlay fades out when focus returns to the hero.
- Initial hero state still only teases the next section at the bottom.

Verification:

- Manually inspect hero state, collapsed state, and return-to-hero state.
- Test with logo art and with title fallback.
- Test across representative item types: movie, series, episode, collection, person, and artist.

## Step 4: Release Native Scrolling Below Primary Content

Goal: allow normal page movement once focus leaves the primary content area.

Tasks:

- Add focus tags or another region signal for lower rows such as cast, additional parts, special features, similar items, and about.
- Map those tags to `.nativeContent`.
- When focus enters `.nativeContent`, update the mode without issuing another vertical correction.
- Ensure future lower-row focus changes do not collapse back to the primary boundary.
- Decide whether returning from lower content to primary content should preserve the current native scroll position or allow the focus engine to reveal the row naturally.

Acceptance criteria:

- Moving farther down the page scrolls normally.
- Lower rows are not pulled back to the primary content collapsed boundary.
- Returning from lower content to primary content does not fight native scroll unless the view is genuinely offscreen.

Verification:

- Manually test focus movement from primary content to cast/about or equivalent lower rows.
- Manually test focus movement back up from lower rows.
- Confirm horizontal row scrolling still works independently.

## Step 5: Replace Legacy Focus Guide Where Practical

Goal: move toward modern SwiftUI focus APIs without making this feature depend on a broad refactor.

Tasks:

- Audit the deprecated `FocusGuide` usages involved in cinematic item detail pages.
- Prefer `.focusSection()`, `@FocusState`, `.defaultFocus`, and `.focusScope` for new components.
- Keep existing `FocusGuide` bridges where removing them would create unnecessary risk.
- If type-specific cinematic scroll containers are introduced later, use native focus APIs there from the start.

Acceptance criteria:

- New code does not deepen dependence on the deprecated focus guide unless it is the smallest safe bridge to existing rows.
- Existing rows keep their current behavior during the migration.
- Focus entry from hero to primary content and back remains deterministic.

Verification:

- Code review focus ownership and default focus behavior.
- Simulator verification is recommended if any focus guide usage changes.

## Step 6: Polish Motion and Edge Cases

Goal: make the interaction feel intentional across real content.

Tasks:

- Tune the collapse animation duration and curve to match tvOS focus motion.
- Use `beginFromCurrentState` or equivalent behavior to avoid harsh interruptions.
- Keep blur, dim, logo/title opacity, and collapsed chrome opacity driven by one normalized progress value where possible.
- Handle short content where the collapsed offset is larger than the available scroll range.
- Handle missing logo, missing backdrop, missing primary content, empty rows, and loading/error states.
- Ensure refreshes or data mutations do not reset the page from content mode back to hero unexpectedly.

Acceptance criteria:

- Collapse animates once and settles cleanly.
- Returning to hero reverses the same visual story.
- Data refreshes do not cause visible scroll jumps.
- Sparse or unusual item data still has a stable focus target.

Verification:

- Test with item types that have resume/next-up/first-available actions and item types that do not.
- Test with missing logo and missing backdrop.
- Test with dense primary content, sparse primary content, empty primary content, and long horizontal rows.
- Test moving quickly between hero, primary content, and lower content.

## Delivery Approach

Implement this as one cohesive change set. The steps above are sequencing guidance for keeping the work understandable while developing, not separate PR boundaries.

Recommended order within the single implementation:

1. Add the region/mode model.
2. Make the collapse target exact.
3. Add collapsed chrome and reserved spacing.
4. Add native lower-content release behavior.
5. Clean up focus ownership where practical.
6. Polish motion and edge cases.

## Risks And Mitigations

- The tvOS focus engine may issue its own scroll during the same moment the app animates the boundary settle.
  Mitigation: only animate on region boundary changes, make the collapsed boundary exact, and stop correcting vertical position after settling.

- Overlay chrome may duplicate controls already present in scroll content.
  Mitigation: choose one source of truth for each control and render it in the overlay only when collapsed, or reserve the existing row's geometry so the visual handoff is stable.

- Lower content may need new focus tags.
  Mitigation: add tags incrementally to rows that participate in the item detail page and keep untagged focus changes as `.unknown` with no scroll correction.

- Replacing `FocusGuide` could expand the change too much.
  Mitigation: use the existing guide for the first implementation and migrate new hero/content components to native SwiftUI focus APIs where practical.

- The exact collapsed boundary may not be reachable on short pages.
  Mitigation: clamp to the available scroll range or use layout reservation so short-content pages still reach a visually valid collapsed state.

## Definition Of Done

- Focus down from the hero fully collapses the hero in one smooth transition.
- Primary content and collapsed chrome settle into a stable content-focused layout.
- Horizontal or internal movement within primary content does not create vertical scroll movement.
- Focus up to the hero expands the hero and hides collapsed chrome.
- Focus down past the primary content lets native tvOS scrolling take over.
- Existing item detail pages preserve their current behavior unless deliberately opted into the shared collapse behavior.
