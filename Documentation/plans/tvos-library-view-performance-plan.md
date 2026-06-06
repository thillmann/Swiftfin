# tvOS Library View Performance Plan

## Goal

Reduce visible stutter while browsing tvOS library views, especially while moving focus through poster grids and loading additional pages.

This plan is based on the Instruments trace at:

- `/Users/timohillmann/Downloads/trace.trace`

The trace was captured on a real Apple TV 4K with the SwiftUI Instruments template. It points to excessive SwiftUI cell updates and expensive focused-cell rendering as the primary library-view performance problem.

## Trace Summary

Capture details:

- Device: Apple TV 4K (3rd generation)
- OS: tvOS 26.5
- App: `Swiftfin tvOS`
- Template: SwiftUI
- Duration: 23.57 seconds
- Instruments: SwiftUI updates, hitches, hangs, Time Profiler

Observed issues:

- 111 hitches in 23.57 seconds.
- Worst hitch: 280 ms.
- One startup hang: 536.17 ms at `00:02.625`.
- Three mid-trace microhangs around the library interaction:
  - 251.13 ms at `00:13.845`
  - 272.57 ms at `00:15.063`
  - 268.80 ms at `00:15.705`
- The SwiftUI update export contained about 1.48 million update rows.
- The repeated hot hierarchy sits under `VirtualizedPosterCellContent<BaseItemDto>` and `VirtualizedLibraryRowContent<BaseItemDto>`.
- Hitch descriptions repeatedly reported:
  - `Potentially expensive app update(s)`
  - `Potentially expensive GPU work`
  - expensive renders with roughly 80 to 199 offscreen passes.

## Current Relevant Code

Primary files:

- `Swiftfin tvOS/Views/PagingLibraryView/PagingLibraryView.swift`
- `Swiftfin tvOS/Views/PagingLibraryView/Components/VirtualizedPosterGrid.swift`
- `Shared/ViewModels/LibraryViewModel/PagingLibraryViewModel.swift`
- `Shared/ViewModels/LibraryViewModel/ItemLibraryViewModel.swift`
- `Shared/ViewModels/LibraryViewModel/RecentlyAddedViewModel.swift`
- `Shared/ViewModels/LibraryViewModel/NextUpLibraryViewModel.swift`
- `Shared/Components/PosterImage.swift`
- `Shared/Components/ImageView.swift`

Important current behavior:

- `PagingLibraryView` renders large libraries through a UIKit-backed `UICollectionView`, which is the right broad direction for tvOS scale.
- `VirtualizedPosterGrid` uses a diffable data source and SwiftUI `UIHostingConfiguration` cells.
- `FocusableHostingCollectionViewCell` updates cell content when focus changes.
- Focus styling is implemented in SwiftUI through `virtualizedCellFocusEffect`.
- On tvOS 26, focused cells use `glassEffect`, scale, and shadow.

## Likely Root Causes

## 1. Focus Changes Rebuild Hosted SwiftUI Cell Content

Current code:

- `FocusableHostingCollectionViewCell.didUpdateFocus(...)` calls `focusChanged`.
- The registered `focusChanged` closure calls `configure(cell, with:isFocused:)`.
- `configure` replaces `cell.contentConfiguration` with a new `UIHostingConfiguration`.

This means every focus transition can rebuild a hosted SwiftUI tree for both focused and unfocused cell states. The trace strongly correlates hitches with virtualized poster cell update hierarchies, so this should be treated as the first fix.

Recommendation:

- Keep each cell's hosted content stable after configuration.
- Move focus-only visual changes into UIKit where possible:
  - `cell.transform`
  - `cell.layer.shadowOpacity`
  - `cell.layer.shadowRadius`
  - `cell.layer.shadowOffset`
  - `cell.layer.zPosition`
  - a lightweight border/focus overlay layer
- Avoid replacing `contentConfiguration` just to change focus.
- If SwiftUI must know focus, pass focus through a tiny reference object owned by the cell instead of replacing the whole hosting configuration.

Preferred implementation shape:

```swift
private final class FocusableHostingCollectionViewCell: UICollectionViewCell {
    private let focusState = VirtualizedCellFocusState()

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)

        let isCellFocused = context.nextFocusedView == self ||
            context.nextFocusedView?.isDescendant(of: self) == true

        coordinator.addCoordinatedAnimations {
            self.layer.zPosition = isCellFocused ? 1 : 0
            self.applyUIKitFocusEffect(isFocused: isCellFocused)
            self.focusState.isFocused = isCellFocused
        }
    }
}
```

Only use the `focusState` option if the overlay text or SwiftUI subtree truly needs focus. Otherwise prefer pure UIKit focus styling.

Acceptance criteria:

- Focus movement no longer assigns a new `contentConfiguration`.
- Cells still scale or highlight on focus.
- Poster overlays still update correctly if they need focus state.
- A follow-up trace shows fewer SwiftUI updates during focus movement.

## 2. tvOS 26 Glass Effect Creates Heavy Offscreen Rendering

Current code:

- `virtualizedCellFocusEffect` applies `glassEffect` for tvOS 26.
- The same focused-cell modifier also applies clipping, scale, and shadow.
- The trace repeatedly reports 80 to 199 offscreen passes and expensive GPU work.

Recommendation:

- Temporarily remove `glassEffect` from virtualized library cells and re-profile.
- If that validates the hypothesis, replace it with a cheaper focus treatment for dense library grids:
  - scale
  - subtle border
  - shadow with conservative radius
  - optional lightweight background material only for list rows if needed
- Reserve full Liquid Glass for lower-density screens where fewer elements update at once.

Suggested replacement:

```swift
clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(isFocused ? 0.28 : 0.10), lineWidth: 1)
    }
    .scaleEffect(isFocused ? 1.04 : 1)
    .shadow(
        color: .black.opacity(isFocused ? 0.35 : 0.18),
        radius: isFocused ? 12 : 3,
        y: isFocused ? 8 : 2
    )
```

If focus effects move to UIKit, apply the same visual values through layer properties instead of SwiftUI modifiers.

Acceptance criteria:

- Focused cells still feel native and readable.
- Offscreen-pass hitch descriptions decrease substantially in a follow-up trace.
- GPU-related hitches decrease during rapid focus movement.

## 3. Grid Updates Rebuild Snapshot and Layout Too Often

Current code:

- `PagingLibraryView.gridView` passes `items: Array(viewModel.elements)`.
- `VirtualizedPosterGrid.updateUIView` always calls `coordinator.update`.
- `Coordinator.update` always:
  - replaces `itemLookup`
  - invalidates layout
  - applies a full diffable snapshot

This creates O(n) work during unrelated SwiftUI invalidations. It is especially suspicious when combined with pagination state changes or focus-driven updates.

Recommendation:

- Cache the previous item IDs in the coordinator.
- Cache layout inputs:
  - collection width
  - poster type
  - display type
  - column count
  - spacing
- Only apply a snapshot when item IDs change.
- Only invalidate layout when layout inputs change.
- For append-only pagination, append new IDs to the existing snapshot instead of rebuilding every ID.

Suggested coordinator state:

```swift
private var lastItemIDs: [Element.ID] = []
private var lastLayoutState: LayoutState?

private struct LayoutState: Equatable {
    let width: CGFloat
    let posterType: PosterDisplayType
    let displayType: LibraryDisplayType
    let columnCount: Int
    let spacing: CGFloat
}
```

Suggested update flow:

```swift
func update(parent: PagingLibraryView.VirtualizedPosterGrid, in collectionView: UICollectionView) {
    self.parent = parent

    let itemIDs = parent.items.map(\.id)
    if itemIDs != lastItemIDs {
        itemLookup = Dictionary(uniqueKeysWithValues: parent.items.map { ($0.id, $0) })
        applySnapshot(itemIDs: itemIDs)
        lastItemIDs = itemIDs
    }

    let layoutState = LayoutState(
        width: collectionView.bounds.width,
        posterType: parent.posterType,
        displayType: parent.displayType,
        columnCount: parent.columnCount,
        spacing: parent.spacing
    )

    if layoutState != lastLayoutState {
        updateLayout(in: collectionView)
        lastLayoutState = layoutState
    }
}
```

Acceptance criteria:

- Normal focus movement does not apply a new diffable snapshot.
- Normal focus movement does not invalidate layout.
- Pagination still appends items correctly.
- Layout changes still update immediately when display type, poster type, or column count changes.

## 4. Avoid Full Item Array Copies in SwiftUI Body

Current code:

- `PagingLibraryView.gridView` uses `Array(viewModel.elements)` inside a view builder.

This copies the full identified array whenever the view recomputes. It is not the biggest trace-backed issue, but it compounds the update cost.

Recommendation:

- Prefer passing a stable array already owned by the view model, or expose a snapshot-like value that only changes when `elements` changes.
- If keeping the current API, ensure `VirtualizedPosterGrid` update caching prevents the copied array from causing snapshot/layout work.

Possible model-level API:

```swift
@Published private(set) var itemSnapshot: [Element] = []
```

Update it only when `elements` changes during refresh, append, or removal.

Acceptance criteria:

- Rendering `PagingLibraryView.body` no longer performs avoidable full collection conversion work.
- The grid still receives stable item ordering and item lookup data.

## 5. Narrow Pagination Invalidation and Duplicate Near-End Events

Current code:

- `loadNextPageIfNeeded` checks `viewModel.backgroundStates.contains(.gettingNextPage)`.
- `backgroundStates` is published on the same broad view model that drives the full library view.
- `willDisplay` and `prefetchItemsAt` can both call `onNearEnd`.

Recommendation:

- Debounce or gate near-end callbacks inside `VirtualizedPosterGrid.Coordinator`.
- Track the last requested threshold/count to avoid repeated requests for the same item count.
- Consider a simple `isPaging` published boolean instead of a set if only one background state is needed for this view.
- Keep paging state reads out of the SwiftUI body path where possible.

Suggested coordinator gate:

```swift
private var lastNearEndItemCount = 0

private func loadNextPageIfNeeded(for index: Int) {
    let nextPageThreshold = max(parent.items.count - parent.columnCount * parent.pagingPrefetchRows, 0)
    guard index >= nextPageThreshold else { return }
    guard parent.items.count != lastNearEndItemCount else { return }

    lastNearEndItemCount = parent.items.count
    parent.onNearEnd()
}
```

Reset `lastNearEndItemCount` when item IDs shrink or refresh.

Acceptance criteria:

- The same near-end threshold does not fire multiple next-page actions.
- Pagination still begins before the user reaches the end.
- Paging state changes do not cause broad visual churn.

## 6. Fix Paging Math Before Comparing Runs

Current code:

- `PagingLibraryViewModel.getNextPage` computes `hasNextPage` with `DefaultPageSize` instead of `pageSize`.
- `RecentlyAddedLibraryViewModel.parameters(for:)` sets `startIndex = page`.
- `NextUpLibraryViewModel.parameters(for:)` sets `startIndex = page`.
- `ItemLibraryViewModel` uses `startIndex = page * pageSize`.

Recommendation:

- Change `hasNextPage = !(pageItems.count < pageSize)`.
- Audit endpoint semantics for `getLatestMedia`, `getItems`, and `getNextUp`.
- If `startIndex` is an item offset for Recently Added and Next Up, change those to `page * pageSize`.
- If either endpoint uses cursor-like page values, add comments explaining the exception.

Acceptance criteria:

- Pagination does not request overlapping pages.
- `hasNextPage` behaves correctly for custom page sizes.
- Trace comparisons are not polluted by duplicate page data or extra requests.

## 7. Tune Poster Image Sizing After Render Fixes

Current code:

- `PosterImage` defaults to max widths of 300 landscape and 200 portrait.
- `VirtualizedPosterGrid` already computes item size.

Recommendation:

- After the focus/render fixes, pass display-aware `maxWidth` into `PosterImage`.
- Use rounded size buckets to keep Jellyfin/Nuke cache reuse high.
- Avoid exact per-pixel request widths.

Suggested approach:

- Landscape grid: bucket to 300, 400, or 500 depending on rendered width and display scale.
- Portrait grid: bucket to 200, 300, or 400.
- List rows: keep the existing smaller row image widths.

Acceptance criteria:

- Image quality remains good on 4K displays.
- Nuke cache keys stay reusable.
- Image decode/download work does not spike during fast scrolling.

## Implementation Order

## Step 1: Remove Focus Reconfiguration

Implement focus styling without replacing `contentConfiguration`.

Tasks:

- Add a UIKit-level focus effect to `FocusableHostingCollectionViewCell`.
- Stop calling `configure(cell, with:isFocused:)` from `focusChanged`.
- Keep `contentConfiguration` assignment limited to initial dequeue/configure and item changes.
- Remove or reduce the SwiftUI `isFocused` dependency if possible.

Verification:

- Run the same library focus movement manually.
- Capture a new SwiftUI trace.
- Compare SwiftUI update volume and hitches against the baseline trace.

## Step 2: Disable Glass in Virtualized Cells and Re-Profile

Tasks:

- Replace tvOS 26 `glassEffect` in `virtualizedCellFocusEffect` with the cheaper non-glass treatment.
- Keep visual polish close enough for a performance test.

Verification:

- Capture a new SwiftUI trace on the same Apple TV.
- Compare:
  - hitch count
  - worst hitch
  - offscreen-pass descriptions
  - GPU-work descriptions

Decision:

- If hitches drop meaningfully, keep glass out of dense library grids.
- If hitches do not drop, inspect Time Profiler for remaining layout or image work before restoring glass.

## Step 3: Cache Snapshot and Layout Updates

Tasks:

- Add `lastItemIDs`.
- Add `LayoutState`.
- Skip `applySnapshot` when item IDs are unchanged.
- Skip `invalidateLayout` when layout inputs are unchanged.
- Prefer append-only snapshot updates for pagination if the diffable API usage stays simple.

Verification:

- Confirm focus movement does not apply snapshots.
- Confirm pagination appends items.
- Confirm display type and poster type changes still relayout correctly.

## Step 4: Fix Paging Math

Tasks:

- Replace `DefaultPageSize` with `pageSize` in `hasNextPage`.
- Audit and fix `startIndex` for Recently Added and Next Up if they are item offsets.
- Add comments where endpoint-specific paging differs.

Verification:

- Confirm page requests use expected offsets.
- Confirm duplicate items do not appear after paging.

## Step 5: Tune Image Request Sizes

Tasks:

- Pass bucketed grid image sizes into `PosterImage`.
- Keep row image sizes unchanged unless separate profiling shows row image pressure.

Verification:

- Compare visual quality on a 4K Apple TV.
- Compare Time Profiler and memory behavior during fast scrolling.

## Follow-Up Profiling Plan

Use the same capture shape for each comparison:

- Device: same Apple TV 4K.
- Template: SwiftUI.
- Duration: 20 to 30 seconds.
- Scenario:
  - Open the same large library.
  - Move focus rapidly across poster cells.
  - Scroll until pagination triggers.
  - Stop recording shortly after new items appear.

Record these metrics for each run:

| Run | Hitch Count | Worst Hitch | Main-Thread Hangs | Offscreen Pass Reports | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| Baseline trace | 111 | 280 ms | 4 | 80-199 passes | Current submitted trace |
| After focus reconfiguration fix | TBD | TBD | TBD | TBD | Expected biggest SwiftUI update reduction |
| After glass simplification | TBD | TBD | TBD | TBD | Expected GPU/offscreen-pass reduction |
| After snapshot/layout caching | TBD | TBD | TBD | TBD | Expected lower update work during paging/layout invalidations |

## Success Criteria

The first performance pass is successful when:

- Hitch count is substantially lower than 111 in the same scenario.
- Worst hitch is below 100 ms, with a stretch goal below 50 ms.
- Mid-interaction main-thread microhangs are gone.
- Expensive offscreen-pass reports are rare or absent during focus movement.
- Focus movement remains visually polished and predictable.
- Pagination still loads before the user reaches the end.

