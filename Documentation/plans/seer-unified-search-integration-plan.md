# Seer Unified Search Integration Plan

## Goal
Integrate Seer results into the existing Search experience so users see a single type-grouped result screen (`Movies`, `TV Shows`, `People`, etc.) with blended Jellyfin and Seer results.

Jellyfin results should keep current navigation behavior, while Seer results should lead to request actions.

## Scope
- Use existing Search sections by content type.
- Blend Seer results into those sections (no top-level Seer-only section).
- Support source-specific rendering and actions.
- Keep rollout tvOS-first, then iOS parity.

## Data Model
Use a thin wrapper enum to minimize mapping overhead:

- `UnifiedSearchResult`
  - `.jellyfin(BaseItemDto)`
  - `.seer(SeerClient.MediaResult)`

Add lightweight computed helpers on the wrapper:
- `kind` (movie, tv, person, etc.)
- `title`
- `source` (`jellyfin` or `seer`)
- `imageSources`

## Search Flow
1. Debounce input (existing behavior).
2. On each query, run in parallel:
   - Jellyfin typed search (existing implementation).
   - Seer `search(query, page: 1)`.
3. Split Seer mixed results by `mediaType`.
4. Merge into existing type buckets.
5. Cancel stale in-flight requests when query changes.

## Merge Strategy (Initial)
- Jellyfin results always have priority in each section.
- Seer should first be used to enrich matching Jellyfin items, then add only unmatched Seer items.
- Avoid duplicate cards for the same movie/show when both sources refer to the same title.

Merge order per section:
1. Start with Jellyfin items as the base list.
2. Build Seer lookup candidates by strongest identifiers:
   - Preferred: TMDB/TVDB external IDs where available.
   - Fallback: normalized title + year heuristic.
3. For each Jellyfin item:
   - If Seer match found, attach Seer metadata to that item (request status/capability, Seer ID).
   - Keep item rendered as the Jellyfin-primary card.
4. Append only Seer items that did not match any Jellyfin item.

This keeps library-first ordering while still exposing request functionality for missing content.

## UI Rendering
Within each type section (`Movies`, `TV Shows`, `People`, ...):
- Render by result source via enum switch.
- Jellyfin items use existing card components and navigation.
- If a Jellyfin item has matched Seer metadata, show a subtle secondary affordance (for example a `Seer` badge or request-status chip) without changing primary navigation.
- Seer items use source-specific request-oriented cards.

Seer cards should visibly communicate source/action:
- Source badge/chip: `Seer`
- Request cue: `Request`

## Interaction Behavior
- Jellyfin tap: navigate to item/person details (current behavior).
- Optional secondary action for Jellyfin items with Seer metadata: open request/status action sheet.
- Seer tap: open request flow and call `SeerClient.request(...)`.

## Seer Availability Gate
UI should decide Seer availability via:
- Seer integration toggle state.
- `SeerrIntegration.serverURL` validity.
- `SeerrIntegration.apiKey` presence.

If unavailable, Search should continue showing Jellyfin results only.

## Error Handling
Support partial success:
- Jellyfin succeeds, Seer fails: show Jellyfin results and soft Seer error state.
- Seer succeeds, Jellyfin fails: show Seer results where possible.

No hard failure for the full screen unless both sources fail fatally.

## Pagination Plan
Current behavior is effectively first-page only for both sources.

Add independent pagination state per source:
- Jellyfin page state
- Seer page state (`currentPage`, `totalPages`, `hasMore`, `isLoading`)

For Seer:
- Request additional `/search?page=n` pages.
- Repartition by type and append into existing grouped sections.
- Trigger per-section load-more when near end.

## Delivery Phases
1. **Phase 1 (tvOS)**
   - Blended type-grouped sections with source-aware rendering.
   - Seer request action wiring.
2. **Phase 2 (iOS parity)**
   - Mirror behavior and UI semantics.
3. **Phase 3 (quality improvements)**
   - Ranking/interleaving refinements.
   - Richer request status presentation.
   - Pagination tuning.
