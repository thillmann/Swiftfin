# tvOS Series Detail Page Plan

## Goal

Replace the current tvOS show detail body with a more cinematic, Apple TV-style series detail page while continuing to use the existing Jellyfin DTOs, routes, image helpers, playback queues, and APIs.

The new page should include:

- A hero area with backdrop art, logo or title, metadata, next-up/resume/first-available episode context, and a favorite button.
- A season selector with one pill per season.
- A continuous episode rail that scrolls through all seasons and lazily loads episodes in both directions.
- A cast and crew overview.
- A lightweight synopsis/about band using the series overview and existing overview route.

Do not include trailer-specific sections from the reference screenshots.

## Existing Code To Reuse

Primary replacement points:

- `Swiftfin tvOS/Views/ItemView/SeriesItemContentView.swift`
- `Swiftfin tvOS/Views/ItemView/Components/EpisodeSelector/EpisodeSelector.swift`
- `Swiftfin tvOS/Views/ItemView/ScrollViews/CinematicScrollView.swift`
- `Shared/ViewModels/ItemViewModel/SeriesItemViewModel.swift`
- `Shared/ViewModels/ItemViewModel/SeasonItemViewModel.swift`

Useful existing components:

- `ItemView.CinematicHeaderView`
- `ItemView.CastAndCrewHStack`
- `ItemView.AboutView`
- `ItemView.PlayButton`
- `ItemView.ActionButtonHStack`

Do not assume any in-branch experimental changes to `SeriesEpisodeSelector.EpisodeCard`, `SeriesEpisodeSelector.EpisodePoster`, or `SeriesEpisodeSelector.EpisodeContent` exist. Treat the new episode card, poster, and content visuals as part of this implementation plan. The older selector/card code can still be used as a reference for routing, focus concepts, and DTO field usage, but the target design should be implemented in new or deliberately replaced components.

Useful existing behavior:

- `SeriesItemViewModel.playButtonItem` already resolves next-up, resume, then first available. Use this for the hero.
- `ItemViewModel.Action.toggleIsFavorite` already maps to Jellyfin favorite/unfavorite APIs.
- `Paths.getSeasons` and `Paths.getEpisodes` already provide the data path for seasons and episodes.
- `EpisodeMediaPlayerQueue(episode:)` already handles episode playback routing.

## Design Direction

The page should feel like a native tvOS media detail surface rather than a generic library list.

Overall visual style:

- Full-screen cinematic backdrop, dimmed and blurred where content scrolls over it.
- Strong dark gradients from the left and bottom of the hero for readable metadata.
- Large show logo when available, with a polished title fallback.
- Low-contrast secondary text, bright primary text, and white/translucent focused controls.
- Rounded image cards with subtle border and gloss only when focused.
- No nested card-heavy layout. Use rails and full-width bands where possible.
- Favor tvOS-native focus behavior, `Button`, `Menu` only where needed, and SwiftUI focus states over custom gesture state.

Reference measurements to preserve the Apple TV-like feel:

- Treat the reference as a 16:9 canvas. Use relative layout values so the design scales across tvOS resolutions.
- Outer content should feel inset from the physical screen, roughly 3.5% horizontally and 4% vertically, with a large rounded viewport frame.
- Hero artwork should occupy the full viewport and remain visible behind all content.
- Hero metadata should sit in the lower-left quadrant, roughly 7-8% from the left edge and 50-55% from the top.
- Hero logo should be large but not poster-sized: roughly 20-25% of viewport width, capped by image aspect ratio.
- Hero copy should be constrained to about 38-45% of viewport width to avoid crossing faces/key art.
- The bottom hero gradient should reach high enough to protect the action buttons and first rail, roughly the bottom 35-45% of the viewport.
- The left hero gradient should protect metadata across roughly the left 45-55% of the viewport.
- The scrolled content state should keep a centered show logo above the season pills, then a single horizontal episode rail.
- Season pills should be large, soft capsules with generous horizontal spacing; selected/focused state should read from across the room.
- Episode cards should use landscape 16:9 images, approximately 20-23% of viewport width, with text content below or in a focused translucent panel.
- Focused cards should grow enough to be unmistakable, but not enough to collide with neighboring rows.
- The content band below the hero should look like blurred dark glass over the backdrop, not a separate opaque page.

Motion and scroll-state behavior:

- Initial focus starts in the hero actions.
- In the initial hero state, the first episode rail should be teased at the bottom edge of the viewport, but the season pills and centered top logo should not be visible yet.
- Moving focus down from the hero should focus the next-up/resume/anchor episode in the episode rail.
- The episode rail is the primary scroll anchor. It should move with normal scroll/focus behavior rather than feeling artificially delayed.
- Supporting chrome should react to the episode rail's vertical progress:
  - the season pill rail fades in and becomes visually locked above the episode rail
  - the centered show logo fades in while moving upward with a slower parallax offset
  - lower follow-up content such as cast and synopsis moves up with a slight delay after the episode rail
- As the episode rail moves up, the hero artwork should blur and darken behind the content band.
- Moving focus back up to the hero should reverse the transition: season pills and centered logo fade out, hero artwork sharpens, and the hero metadata becomes primary again.
- The anchor episode should be the first focused card after moving down, matching `playButtonItem` when available.
- Avoid abrupt opacity swaps. Prefer scroll progress-driven opacity, blur, and offset values.
- Keep motion subtle enough for tvOS: cinematic and spatial, not springy or busy.

## Proposed Structure

Create a tvOS-specific series detail component group:

```text
Swiftfin tvOS/Views/ItemView/Components/SeriesDetail/
  SeriesDetailView.swift
  SeriesHeroView.swift
  SeriesFavoriteButton.swift
  SeriesSeasonPillRail.swift
  SeriesEpisodeTimelineView.swift
  SeriesEpisodeTimelineViewModel.swift
  SeriesEpisodeCardView.swift
  SeriesCastAndCrewRail.swift
  SeriesSynopsisBandView.swift
  SeriesDetailDisplayModels.swift
```

`ItemView.SeriesItemContentView` should become the tvOS entry point for the new composition:

```swift
SeriesDetailView(viewModel: viewModel)
```

The screen can either:

- extend `CinematicScrollView` with a series-specific header slot, or
- add a `SeriesCinematicScrollView` used only when `item.type == .series`.

Prefer the smaller change after implementation exploration. If the generic scroll view becomes awkward, keep series-specific layout separate.

Also add a reusable virtualized horizontal rail primitive that the series episode timeline can use first, but which is not coupled to series DTOs:

```text
Swiftfin tvOS/Components/VirtualizedRail/
  VirtualizedHorizontalRail.swift
  VirtualizedHorizontalRailViewModel.swift
  VirtualizedRailFocusID.swift
```

The reusable rail should own the hard scrolling mechanics:

- stable item identity
- bidirectional append/prepend
- lazy load triggers near either edge
- programmatic scroll to an item ID
- focus restoration after prepends
- optional loading/error sentinels at the head and tail

The series timeline should own series-specific behavior:

- season ordering
- Jellyfin episode paging
- season pill jump targets
- mapping episodes into display models
- play/detail actions

## Display Models

Avoid passing full DTOs deep through presentational components. Map `BaseItemDto` and `BaseItemPerson` near the screen boundary into small display models.

Example display models:

```swift
struct SeriesHeroDisplayModel {
    let title: String
    let logoImageSource: ImageSource
    let backdropImageSource: ImageSource
    let metadata: [String]
    let episodeContextLine: String?
    let episodeOverview: String?
    let starringLine: String?
    let isFavorite: Bool
}

struct SeasonPillDisplayModel: Identifiable {
    let id: String
    let title: String
    let isSelected: Bool
    let isLoaded: Bool
}

struct EpisodeCardDisplayModel: Identifiable {
    let id: String
    let imageSource: ImageSource
    let fallbackSystemImageName: String
    let seasonNumber: Int?
    let episodeNumber: Int?
    let title: String
    let overview: String
    let releaseDate: String?
    let duration: String?
    let playbackProgress: CGFloat?
    let isPlayed: Bool
    let isUnaired: Bool
    let isMissing: Bool
}

struct CastCreditDisplayModel: Identifiable {
    let id: String
    let name: String
    let role: String?
    let imageSource: ImageSource
}

struct SeriesSynopsisDisplayModel {
    let title: String
    let genres: String?
    let synopsis: String
    let releaseYear: String?
    let officialRating: String?
}
```

Keep DTOs in the container/view model layer for actions:

- `onPlayEpisode(BaseItemDto)`
- `onOpenEpisode(BaseItemDto)`
- `onFavoriteToggle()`
- `onOpenPerson(BaseItemPerson)`
- `onOpenOverview(BaseItemDto)`

## Hero

Use the existing `playButtonItem` selection for the hero episode context.

Hero content:

- Backdrop image from the series backdrop.
- Logo image from `.logo`; fallback to show title.
- Metadata row:
  - `TV Show`
  - primary genre or first few genres
  - release year of the latest or hero episode when available
  - runtime of `playButtonItem`
  - official rating when available
- Episode context from `playButtonItem`:
  - season/episode label
  - episode title
  - episode overview
- Favorite button, not watchlist.
- Optional starring line from first cast members.

Favorite button behavior:

- Use Jellyfin favorite state: `viewModel.item.userData?.isFavorite`.
- Toggle with `viewModel.send(.toggleIsFavorite)`.
- Label examples:
  - not favorite: `Favorite`
  - favorite: `Favorited`
- Icons:
  - not favorite: `heart`
  - favorite: `heart.fill` or checkmark plus heart if preferred.
- Focused state:
  - white capsule
  - black label/icon
  - slight scale
- Unfocused state:
  - translucent material/dark capsule
  - white label/icon

## Season Pills

Replace the current menu-style selector with a horizontal pill rail.

Behavior:

- One pill per season.
- The initial selected season should be the season of `playButtonItem`, matching the current behavior.
- Selecting a pill jumps to the first episode of that season inside the continuous episode rail.
- Selecting a pill does not filter the rail to that season.
- If the target season is not loaded yet, load enough data to materialize that season's first episode, then scroll to it.
- If only one season exists, keep the pill visible for consistency unless later UX review prefers hiding it.

Pill states:

- normal: text-only or low-opacity capsule.
- focused: brighter capsule, slight scale, stronger text.
- selected: filled capsule.
- selected and focused: strongest fill, white or near-white background, dark text.
- loading target: selected treatment with subtle progress indicator or disabled interaction.
- unavailable/empty: dimmed but still selectable if it can show an empty state.

## Continuous Episode Timeline

The episode list is the most important part of the page.

The current implementation loads episodes for only the selected season. Replace that with a timeline model that presents all seasons as one continuous rail and lazily loads episodes.

Requirements:

- Continuous horizontal rail across all seasons.
- Episode cards remain grouped by order, but no separate per-season rails.
- Lazy loading must work forward and backward.
- Default position should be the season currently being watched, based on `playButtonItem`.
- Season pills jump to the first episode of the selected season inside the continuous rail.
- Loading should preserve focus and avoid visible jumps.

### Timeline View Model

Add a tvOS-specific view model, owned by `SeriesDetailView`, for the episode timeline.

Conceptual API:

```swift
@MainActor
final class SeriesEpisodeTimelineViewModel: ViewModel, Stateful {
    enum Anchor {
        case playButtonItem(BaseItemDto?)
        case season(id: String)
    }

    @Published private(set) var items: [SeriesEpisodeTimelineItem] = []
    @Published private(set) var selectedSeasonID: String?
    @Published private(set) var state: State = .initial
    @Published private(set) var loadingDirections: Set<LoadingDirection> = []

    func refresh(series: BaseItemDto, seasons: [BaseItemDto], anchor: Anchor)
    func loadMoreForwardIfNeeded(near itemID: String)
    func loadMoreBackwardIfNeeded(near itemID: String)
    func jumpToSeason(_ seasonID: String)
}
```

Track per-season paging metadata:

```swift
struct SeasonPagingState {
    let season: BaseItemDto
    var previousStartIndex: Int?
    var nextStartIndex: Int?
    var hasPreviousPage: Bool
    var hasNextPage: Bool
    var loadedEpisodeIDs: Set<String>
}
```

Use `Paths.getEpisodes(seriesID:parameters:)` with:

- `fields = .MinimumFields`
- `enableUserData = true`
- `seasonID = season.id`
- `startIndex`
- `limit`
- missing episode behavior consistent with current settings

### Bidirectional Loading Strategy

Because Jellyfin episode paging is season-oriented, keep paging state per season but present one flattened list.

Initial load:

1. Find anchor season from `playButtonItem.seasonID`.
2. If missing, use first season.
3. Load the first page for the anchor season.
4. If the anchor episode is not in the first page, prefer `Paths.GetEpisodesParameters(adjacentTo: anchorEpisode.id, limit: pageSize)` to materialize a window around the anchor without scanning from the beginning.
5. If `adjacentTo` cannot be used for the specific request, use a capped season-level scan or page forward within that season until the anchor episode is found, then fall back to the first loaded episode.
6. Preload one neighboring page or season in each direction when cheap enough to reduce empty edges.

Forward loading:

1. When focus or appearance nears the last loaded items, load the next page for the current tail season.
2. If that season has no next page, load the first page of the next season.
3. Append results without replacing existing items.

Backward loading:

1. When focus or appearance nears the first loaded items, load the previous page for the current head season.
2. If that season has no previous page, load the last page or an appropriate page of the previous season.
3. Prepend results while preserving the visible focused item.

Backward paging caveat:

Jellyfin pagination is `startIndex` plus `limit`, so loading the "last page" of a previous season may require knowing total record count. If `ItemsResult.totalRecordCount` is available from the response, use it to compute the previous season's final page. If it is not available through the generated DTO, fall back to loading the previous season forward from index 0 until the final page is known, but do that only on explicit backward navigation or season jump to avoid unnecessary work.

Focus preservation:

- Keep a compound focus identity as the source of truth, not just the episode ID.
- When prepending, restore focus to the same episode ID after the data update.
- Preserve which part of the card had focus: poster/play or content/details.
- Use stable IDs from `BaseItemDto.id`.
- Avoid index-based identity.

Example focus identity:

```swift
struct EpisodeTimelineFocusID: Hashable {
    enum Region: Hashable {
        case poster
        case content
    }

    let episodeID: String
    let region: Region
}
```

Lazy load triggers:

- `onAppear` for the first and last few rendered cards.
- `onChange(of: focusedTimelineID)` when focus moves within a threshold of either loaded edge.

## Episode Card

Implement the episode card/poster/content treatment as part of this work. Do not depend on any previous branch changes to `EpisodeCard`, `EpisodePoster`, or `EpisodeContent`.

The baseline/current episode selector can be used as a reference for:

- playing an episode with `EpisodeMediaPlayerQueue(episode:)`
- opening episode details through the router
- reading `runTimeLabel`, `episodeLocator`, `airDateLabel`, `isUnaired`, `isMissing`, and user playback data from `BaseItemDto`
- separating poster focus from content focus

Card layout:

- Landscape feature image/poster.
- Bottom-left overlay inside image:
  - play icon when unwatched or resumable
  - replay icon when watched
  - progress bar when partially watched
  - duration label
- Text below:
  - `EPISODE N`
  - title
  - description
  - release date

Actions:

- Poster focus/action plays the episode.
- Content focus/action opens episode detail.

Visual states:

- Unfocused:
  - poster slightly dimmed
  - content transparent
  - secondary text muted
- Poster focused:
  - poster scales up
  - border/gloss highlight appears around poster
  - metadata overlay becomes fully opaque
  - content below gets a subtle linked highlight
  - select routes to video player
- Content focused:
  - poster does not scale
  - bottom content becomes the primary focused translucent card
  - select routes to episode item detail
- Linked:
  - used when poster is focused and content should visually belong to it without becoming the active focus target.
- Watched:
  - replay icon
  - no progress bar
- Partially watched:
  - play icon
  - visible progress bar
- Unaired:
  - no playable treatment
  - show air date or release date prominently
- Missing:
  - disabled or dimmed play treatment
  - keep details focus available if there is useful metadata
- Image failure:
  - use existing `SystemImageContentView` fallback.

## Cast And Crew

The current `ItemView.CastAndCrewHStack` can stay as the first implementation, but the target design is a stronger visual rail:

- circular headshots
- name below
- character/role below in secondary text
- focused portrait scales and gets a subtle ring
- missing image uses a person fallback symbol

Map `BaseItemPerson` into `CastCreditDisplayModel` before rendering.

## Synopsis Band

Create a lightweight synopsis/about section instead of a dense metadata card stack.

Content:

- Synopsis from `viewModel.item.overview`, with truncation and a "More" action that opens the existing overview route.
- Optional compact metadata that is already available on the series DTO, such as release year, genres, and official rating.
- Do not fetch per-episode media streams just to build audio/subtitle language lists in the first implementation.

Design:

- Use a broad dark/translucent information band over the blurred backdrop.
- Avoid tiny dense text where possible, but keep the section scan-friendly.
- Keep headings and text compact enough for tvOS.

## States To Cover

Screen states:

- initial loading
- content
- error
- background refresh

Hero states:

- logo loaded
- title fallback
- favorite
- not favorite
- favorite toggle in progress
- sparse metadata
- missing backdrop

Season selector states:

- normal
- focused
- selected
- selected and focused
- loading jump target
- only one season
- many seasons

Episode timeline states:

- initial loading
- loading forward
- loading backward
- empty
- page error forward
- page error backward
- selected season not loaded yet
- focus restored after prepend

Episode card states:

- unfocused
- poster focused
- content focused
- linked content while poster focused
- watched
- partially watched
- unaired
- missing
- no image
- long title
- long overview
- no runtime
- no release date

Cast and crew states:

- normal
- focused
- missing image
- long names
- no role

Synopsis band states:

- long synopsis
- no synopsis
- sparse metadata

## SwiftUI Previews

Add previews beside the components using simple fixtures and preview assets.

Recommended previews:

- `SeriesHeroView`
  - favorited
  - not favorited
  - logo fallback title
  - sparse metadata
- `SeriesFavoriteButton`
  - normal, focused, favorited, unfavorited
- `SeriesSeasonPillRail`
  - many seasons
  - selected season
  - focused selected season
  - loading target
- `SeriesEpisodeCardView`
  - unfocused
  - poster focused
  - content focused
  - watched
  - partially watched
  - unaired
  - missing poster
- `SeriesEpisodeTimelineView`
  - initial loading
  - loaded across multiple seasons
  - loading forward
  - loading backward
  - empty
  - error
- `SeriesCastAndCrewRail`
  - normal
  - focused
  - missing image
- `SeriesSynopsisBandView`
  - sparse metadata
  - long synopsis
  - no synopsis

Use simple in-code display model fixtures for previews. If preview artwork is useful, add a small tvOS preview asset set as part of the implementation rather than assuming one already exists.

## Open Implementation Notes

- Confirm whether `ItemsResult.totalRecordCount` is available from the generated Jellyfin API response for `getEpisodes`. This affects efficient backward loading into the previous season.
- If `CollectionHStack` makes prepend focus preservation difficult, consider a native `ScrollView(.horizontal)` plus `LazyHStack`, or a small adapter that can scroll to stable IDs after data changes.
- Keep the existing favorite API rather than introducing a watchlist abstraction.
- Keep the hero action source as `SeriesItemViewModel.playButtonItem`.
- Keep missing episode visibility aligned with existing user settings.
