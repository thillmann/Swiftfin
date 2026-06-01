# Seerr Unified Search Integration Plan

## Goal
Integrate Seerr results into the existing Search experience so users see a single type-grouped result screen (`Movies`, `TV Shows`, `People`, etc.) with blended Jellyfin and Seerr results.

Jellyfin results should keep current navigation behavior, while Seerr results should lead to request actions.

## Implementation Status (as of June 1, 2026)
Implemented:
- Shared `SeerrClient` and `SeerrIntegration` services are wired for search, status probing, and request submission.
- Unified search supports mixed-source results via `UnifiedSearchResult` with source-aware rendering.
- Seerr results are merged into Jellyfin type buckets, with duplicate suppression via normalized title/year matching.
- Request flow UI exists for Seerr items (`SeerrRequestView`) and is reachable from both iOS and tvOS search.
- Seerr integration settings are present with validation and connection-status handling.
- User-facing naming and messaging are standardized to `Seerr` across app code and this plan.

Partially implemented:
- Cross-source enrichment of Jellyfin cards with attached Seerr metadata is limited; current behavior is primarily merge-and-append of unmatched Seerr items.

Not implemented yet:
- Independent source pagination beyond first-page behavior.
- Ranked interleaving refinements and richer request-status presentation.

## Scope
- Use existing Search sections by content type.
- Blend Seerr results into those sections (no top-level Seerr-only section).
- Support source-specific rendering and actions.
- Keep rollout tvOS-first, then iOS parity.

## Data Model
Use a thin wrapper enum to minimize mapping overhead:

- `UnifiedSearchResult`
  - `.jellyfin(BaseItemDto)`
  - `.seer(SeerrClient.MediaResult)`

Add lightweight computed helpers on the wrapper:
- `kind` (movie, tv, person, etc.)
- `title`
- `source` (`jellyfin` or `seer`)
- `imageSources`

## Search Flow
1. Debounce input (existing behavior).
2. On each query, run in parallel:
   - Jellyfin typed search (existing implementation).
   - Seerr `search(query, page: 1)`.
3. Split Seerr mixed results by `mediaType`.
4. Merge into existing type buckets.
5. Cancel stale in-flight requests when query changes.

## Merge Strategy (Initial)
- Jellyfin results always have priority in each section.
- Seerr should first be used to enrich matching Jellyfin items, then add only unmatched Seerr items.
- Avoid duplicate cards for the same movie/show when both sources refer to the same title.

Merge order per section:
1. Start with Jellyfin items as the base list.
2. Build Seerr lookup candidates by strongest identifiers:
   - Preferred: TMDB/TVDB external IDs where available.
   - Fallback: normalized title + year heuristic.
3. For each Jellyfin item:
   - If Seerr match found, attach Seerr metadata to that item (request status/capability, Seerr ID).
   - Keep item rendered as the Jellyfin-primary card.
4. Append only Seerr items that did not match any Jellyfin item.

This keeps library-first ordering while still exposing request functionality for missing content.

## UI Rendering
Within each type section (`Movies`, `TV Shows`, `People`, ...):
- Render by result source via enum switch.
- Jellyfin items use existing card components and navigation.
- If a Jellyfin item has matched Seerr metadata, show a subtle secondary affordance (for example a `Seerr` badge or request-status chip) without changing primary navigation.
- Seerr items use source-specific request-oriented cards.

Seerr cards should visibly communicate source/action:
- Source badge/chip: `Seerr`
- Request cue: `Request`

## Interaction Behavior
- Jellyfin tap: navigate to item/person details (current behavior).
- Optional secondary action for Jellyfin items with Seerr metadata: open request/status action sheet.
- Seerr tap: open request flow and call `SeerrClient.request(...)`.

## Seerr Availability Gate
UI should decide Seerr availability via:
- Seerr integration toggle state.
- `SeerrIntegration.serverURL` validity.
- `SeerrIntegration.apiKey` presence.

If unavailable, Search should continue showing Jellyfin results only.

## Error Handling
Support partial success:
- Jellyfin succeeds, Seerr fails: show Jellyfin results and soft Seerr error state.
- Seerr succeeds, Jellyfin fails: show Seerr results where possible.

No hard failure for the full screen unless both sources fail fatally.

## Pagination Plan
Current behavior is effectively first-page only for both sources.

Add independent pagination state per source:
- Jellyfin page state
- Seerr page state (`currentPage`, `totalPages`, `hasMore`, `isLoading`)

For Seerr:
- Request additional `/search?page=n` pages.
- Repartition by type and append into existing grouped sections.
- Trigger per-section load-more when near end.

## Delivery Phases
1. **Phase 1 (tvOS)**
   - Blended type-grouped sections with source-aware rendering.
   - Seerr request action wiring.
2. **Phase 2 (iOS parity)**
   - Mirror behavior and UI semantics.
3. **Phase 3 (quality improvements)**
   - Ranking/interleaving refinements.
   - Richer request status presentation.
   - Pagination tuning.
