# tvOS Library View Performance Plan

## Goal

Reduce visible stutter while browsing tvOS library views, especially while moving focus through poster grids and loading additional pages.

This plan started from the Instruments trace at:

- `/Users/timohillmann/Downloads/trace.trace`

Follow-up traces were captured after incremental fixes at:

- `/Users/timohillmann/Downloads/new.trace`
- `/Users/timohillmann/Downloads/new2.trace`

The traces were captured on a real Apple TV 4K with the SwiftUI Instruments template. The original trace pointed to excessive SwiftUI cell updates and expensive focused-cell rendering. The follow-up traces refined that conclusion: Liquid Glass itself should remain part of the visual design, but it must only be instantiated for the focused cell, focus movement must not rebuild hosted cell content, and the most noticeable remaining stutter appears when new rows/pages are loaded.

## Status at This Point

Already implemented in the current performance pass:

- Focus changes no longer replace each cell's `UIHostingConfiguration`.
- Cell focus is passed into SwiftUI through a small `VirtualizedCellFocusState` object owned by the collection-view cell.
- tvOS 26 glass is no longer installed as `.glassEffect(.identity)` on every unfocused cell.
- The transparent glass overlay experiment was removed because it dark-blurred poster art.
- Focus zoom, shadow, and z-position have been moved to `FocusableHostingCollectionViewCell` and animated through `UIFocusAnimationCoordinator`.
- Near-end pagination callbacks are gated in `VirtualizedPosterGrid.Coordinator` so `willDisplay` and `prefetchItemsAt` do not repeatedly request the same item count.
- `VirtualizedPosterGrid.Coordinator` now caches item IDs and layout inputs so focus movement and unrelated SwiftUI invalidations do not rebuild snapshots or invalidate layout.
- Append-only pagination updates now append new diffable snapshot IDs instead of rebuilding every ID.
- `PagingLibraryView` now passes a view-model-owned `itemSnapshot` instead of creating `Array(viewModel.elements)` in the view builder.
- Paging math now uses `pageSize` for `hasNextPage`; normal item libraries and Next Up use `startIndex = page * pageSize`, while Recently Added keeps its existing exclude-ID paging workaround.
- `VirtualizedPosterGrid.Coordinator` now keeps a 36-item poster image working set preheated through Nuke around the visible/prefetched range.

Still to verify with the next profile:

- Whether the near-end gate reduces the stutter observed when new rows load.
- Whether the 36-item image preheat window reduces row-load stutters.
- Whether any remaining row-load hitches are dominated by item page fetch timing, snapshot insertion, cell instantiation, image decode work, or another source.

Not done yet:

- Display-aware poster image request sizing.
- Follow-up device profile for the 36-item image preheat window.

## Trace Summary

Capture details:

- Device: Apple TV 4K (3rd generation)
- OS: tvOS 26.5
- App: `Swiftfin tvOS`
- Template: SwiftUI
- Duration: 23.57 seconds
- Instruments: SwiftUI updates, hitches, hangs, Time Profiler

Original baseline issues:

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

Follow-up profiling learnings:

- Removing focus-time `UIHostingConfiguration` replacement reduced the evidence that virtualized cell body rebuilds were the dominant focus problem.
- Applying `.glassEffect(.identity)` to every unfocused cell was still expensive. Even visually inactive glass contributed to glass/cache/shape update labels.
- Making glass focused-only reduced glass-related update labels substantially.
- A clear glass overlay over the poster image is visually wrong: it refracts and dark-blurs the poster underneath.
- Applying focused glass directly to focused content preserves the intended style without the full-poster blur.
- SwiftUI focus animation is fragile when the focused and unfocused branches have different glass modifier trees. UIKit cell-level transform/shadow animation is more reliable for the focus zoom.
- Follow-up traces and manual observation both point to pagination/new-row loading as a major remaining source of visible stutter.
- The latest device profile after snapshot/layout caching and paging math is better overall, but visible stutters still happen when new rows load.
- The next investigation should separate page data timing from image work: item pages are already requested before the end of the current data set, but poster images are still loaded by `LazyImage` when cells are instantiated.
- A 36-item image preheat window matches the expected maximum working set: about 24 on-screen items plus one extra row before and after the visible range.

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
- UIKit owns onscreen/offscreen cell detection and reuse. The app should not force hidden cells to render just to keep work warm.
- The current performance-pass implementation keeps hosted cell content stable across focus changes and passes focus through a small cell-owned reference object.
- Focus zoom/shadow is now handled at the `UICollectionViewCell` layer through the UIKit focus animation coordinator.
- SwiftUI focus state is retained only for visuals that need SwiftUI, such as the focused-only tvOS 26 glass treatment and poster overlay changes.
- On tvOS 26, only the focused cell instantiates `glassEffect`.
- `VirtualizedPosterGrid.Coordinator` skips diffable snapshot and layout work when item IDs and layout inputs are unchanged.
- `PagingLibraryViewModel.itemSnapshot` provides the stable array used by the tvOS grid.

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

## 2. Glass Was Misapplied, Not Simply Wrong

Original code:

- `virtualizedCellFocusEffect` applies `glassEffect` for tvOS 26.
- The same focused-cell modifier also applies clipping, scale, and shadow.
- Unfocused cells use `.glassEffect(.identity)`.
- The trace repeatedly reports 80 to 199 offscreen passes and expensive GPU work.

What follow-up profiling showed:

- The visual design should keep Liquid Glass.
- `.glassEffect(.identity)` on every cell is not free and should be avoided in dense grids.
- A focused-only `.glassEffect(.regular.interactive())` path greatly reduces glass update labels.
- A separate clear glass overlay over the poster image causes the focused poster to look dark and blurred.
- SwiftUI scale/shadow animation can stop working when the focus state switches between structurally different glass/non-glass branches.

Recommendation:

- Keep Liquid Glass as the focused visual style.
- Do not install `.glassEffect(.identity)` on unfocused cells.
- Do not use a transparent glass overlay above poster images.
- Apply glass directly to the focused cell content only.
- Move focus zoom/shadow to `FocusableHostingCollectionViewCell` using UIKit transforms/layer shadows coordinated by `UIFocusAnimationCoordinator`.
- Keep SwiftUI's focus dependency as narrow as possible: glass on/off and poster overlay state only.

Suggested tvOS 26 shape:

```swift
@ViewBuilder
func virtualizedCellFocusEffect(_ isFocused: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    if #available(tvOS 26.0, *) {
        if isFocused {
            clipShape(shape)
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            clipShape(shape)
        }
    } else {
        clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(isFocused ? 0.24 : 0.12), lineWidth: 1)
            }
    }
}
```

Suggested UIKit focus animation:

```swift
coordinator.addCoordinatedAnimations {
    self.focusState.isFocused = isCellFocused
    self.transform = isCellFocused ? CGAffineTransform(scaleX: 1.06, y: 1.06) : .identity
    self.layer.zPosition = isCellFocused ? 1 : 0
    self.layer.shadowOpacity = isCellFocused ? 0.45 : 0.22
    self.layer.shadowRadius = isCellFocused ? 24 : 4
    self.layer.shadowOffset = CGSize(width: 0, height: isCellFocused ? 14 : 2)
}
```

Acceptance criteria:

- Focused cells keep the intended Liquid Glass style.
- Unfocused cells do not instantiate glass.
- Focused posters are not dark-blurred by an overlay.
- Focus zoom/shadow animates consistently.
- Glass update labels and offscreen-pass reports stay materially lower than the baseline.

## 3. Narrow Pagination Invalidation and Duplicate Near-End Events

Current code:

- `loadNextPageIfNeeded` checks `viewModel.backgroundStates.contains(.gettingNextPage)`.
- `backgroundStates` is published on the same broad view model that drives the full library view.
- `willDisplay` and `prefetchItemsAt` can both call `onNearEnd`.
- Every qualifying visible/prefetched index can call into the near-end path for the same item count.

Follow-up profiling/manual observation:

- The most noticeable remaining stutter happens when new rows are loaded.
- The traces include near-end backtraces through both `willDisplay` and `prefetchItemsAt`.
- This makes pagination gating a high-priority fix, not merely a cleanup.

Recommendation:

- Debounce or gate near-end callbacks inside `VirtualizedPosterGrid.Coordinator`.
- Track the last requested threshold/count to avoid repeated requests for the same item count.
- Consider a simple `isPaging` published boolean instead of a set if only one background state is needed for this view.
- Keep paging state reads out of the SwiftUI body path where possible.

Suggested coordinator gate:

```swift
private var lastNearEndItemCount = 0
private var isNearEndCallbackScheduled = false

private func loadNextPageIfNeeded(for index: Int) {
    let itemCount = parent.items.count
    let nextPageThreshold = max(itemCount - parent.columnCount * parent.pagingPrefetchRows, 0)

    guard index >= nextPageThreshold else { return }
    guard itemCount > lastNearEndItemCount else { return }
    guard !isNearEndCallbackScheduled else { return }

    lastNearEndItemCount = itemCount
    isNearEndCallbackScheduled = true

    DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.isNearEndCallbackScheduled = false
        self.parent.onNearEnd()
    }
}
```

Reset `lastNearEndItemCount` when item IDs shrink or refresh.

Acceptance criteria:

- The same near-end threshold does not fire multiple next-page actions.
- Pagination still begins before the user reaches the end.
- Paging state changes do not cause broad visual churn.

## 4. Grid Updates Rebuild Snapshot and Layout Too Often

Previous code:

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

Status:

- Implemented in the current performance pass.
- Needs follow-up profiling to confirm focus movement no longer applies snapshots or invalidates layout.

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

## 5. Avoid Full Item Array Copies in SwiftUI Body

Previous code:

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

Status:

- Implemented in the current performance pass with `PagingLibraryViewModel.itemSnapshot`.
- `PagingLibraryView.gridView` and the empty-state check now read `itemSnapshot`.

Acceptance criteria:

- Rendering `PagingLibraryView.body` no longer performs avoidable full collection conversion work.
- The grid still receives stable item ordering and item lookup data.

## 6. Fix Paging Math Before Comparing Runs

Previous code:

- `PagingLibraryViewModel.getNextPage` computes `hasNextPage` with `DefaultPageSize` instead of `pageSize`.
- `RecentlyAddedLibraryViewModel.parameters(for:)` sets `startIndex = page`.
- `NextUpLibraryViewModel.parameters(for:)` sets `startIndex = page`.
- `ItemLibraryViewModel` uses `startIndex = page * pageSize`.
- Recently Added also uses `excludeItemIDs` to work around endpoint paging behavior.

Recommendation:

- Change `hasNextPage = !(pageItems.count < pageSize)`.
- Audit endpoint semantics for `getLatestMedia`, `getItems`, and `getNextUp`.
- If `startIndex` is an item offset for Recently Added and Next Up, change those to `page * pageSize`.
- If either endpoint uses cursor-like page values, add comments explaining the exception.
- If an endpoint uses `excludeItemIDs` to page around duplicate/unstable results, do not also apply an offset unless server behavior proves the offset is applied before exclusions.

Acceptance criteria:

- Pagination does not request overlapping pages.
- `hasNextPage` behaves correctly for custom page sizes.
- Trace comparisons are not polluted by duplicate page data or extra requests.

Status:

- Implemented in the current performance pass.
- `PagingLibraryViewModel.getNextPage` now uses `pageSize` for `hasNextPage`.
- Next Up uses `startIndex = page * pageSize`.
- Recently Added intentionally does not use `startIndex = page * pageSize`; it pages from the filtered result by excluding already-loaded IDs to avoid double-skipping if the server applies `excludeItemIDs` before `startIndex`.

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

## 8. Preload Upcoming Page and Image Work Earlier

Current code:

- `PagingLibraryView` uses `pagingPrefetchRows = 8`.
- `VirtualizedPosterGrid.Coordinator.loadNextPageIfNeeded` starts the next page when the highest visible or prefetched index reaches `itemCount - columnCount * pagingPrefetchRows`.
- In grid mode, that means data requests begin roughly 32 items before the end for landscape grids and 48 items before the end for portrait/square grids.
- `PosterImage` uses `LazyImage`, so poster image fetch/decode starts when the SwiftUI cell content is instantiated.
- `VirtualizedPosterGrid.Coordinator` now uses Nuke `ImagePrefetcher` to keep 36 poster image URLs warm around the visible or prefetched index range.
- The 36-item window is an image preheat window, not a manual render window. UIKit still decides which cells are onscreen, offscreen, created, and reused.

Recommendation:

- First confirm whether the row-load hitch aligns with item append/snapshot insertion or with image fetch/decode after cells appear.
- If data arrives too late, increase the page prefetch distance or page size carefully; avoid cascading page requests that load too much of a large library at once.
- If images still dominate, tune the 36-item preheat window, prefetch concurrency, or request sizing.
- Preserve `UICollectionView` virtualization; avoid manually rendering extra hidden cells unless profiling proves cell instantiation itself is the remaining bottleneck.
- Prefer bounded image preheating for the next one to two rows, using the same bucketed `maxWidth` values planned for display-aware poster sizing.
- Consider keeping fetched page data in a pending buffer and committing it to the collection view during a quieter moment if snapshot insertion itself is the hitch.

Acceptance criteria:

- New row data and poster images are ready before focus reaches the row.
- Memory and network usage remain bounded during rapid scrolling.
- Row-load hitches decrease in a follow-up device profile.

## Implementation Order

## Step 1: Remove Focus Reconfiguration

Keep hosted cell content stable across focus transitions.

Tasks:

- Stop calling `configure(cell, with:isFocused:)` from `focusChanged`.
- Keep `contentConfiguration` assignment limited to initial dequeue/configure and item changes.
- If SwiftUI still needs focus, pass it through a small cell-owned reference object rather than replacing hosting configuration.

Verification:

- Run the same library focus movement manually.
- Capture a new SwiftUI trace.
- Compare SwiftUI update volume and hitches against the baseline trace.

Status:

- Done.
- Follow-up traces showed virtualized cell rebuilds were no longer the dominant focus issue.
- The latest device profile verified UIKit-driven focus animation is acceptable.

## Step 2: Scope Glass and Move Focus Animation to UIKit

Tasks:

- Keep Liquid Glass for the focused item.
- Remove `.glassEffect(.identity)` from unfocused cells.
- Avoid transparent glass overlays above poster images.
- Apply focused glass directly to focused content.
- Move scale/shadow/z-position animation to `FocusableHostingCollectionViewCell`.

Verification:

- Capture a new SwiftUI trace on the same Apple TV.
- Compare:
  - hitch count
  - worst hitch
  - offscreen-pass descriptions
  - GPU-work descriptions
  - glass update labels such as `GlassAppearanceScaleEffect`, `GlassEffectShapeModifier`, and `GlassContainerCache.UnwrappedMaterial`
- Manually verify focus animation and poster clarity.

Decision:

- Keep focused-only glass if glass labels remain reduced and the focused visual is correct.
- If focused glass still causes unacceptable GPU/offscreen work, explore a reduced glass shape/tint before removing the design treatment entirely.

Status:

- Focused-only glass materially reduced glass update labels.
- Transparent overlay glass was rejected because it dark-blurred the poster image.
- SwiftUI scale/shadow was moved out of the glass branch because animation was unreliable across different modifier trees.
- UIKit focus animation is implemented in the current performance pass and needs confirmation in the next device run.

## Step 3: Gate Pagination Triggers

Tasks:

- Add a coordinator-level near-end gate keyed by item count.
- Coalesce same-turn `willDisplay` and `prefetchItemsAt` triggers.
- Reset the gate when item IDs shrink or a refresh replaces the data set.

Verification:

- Confirm each loaded item count can trigger at most one next-page request.
- Confirm pagination still starts before the user reaches the end.
- Re-profile the same interaction with emphasis on the moment new rows load.

Status:

- Implemented in the current performance pass.
- Needs follow-up profiling to confirm row-load stutter is reduced.

## Step 4: Cache Snapshot and Layout Updates

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

Status:

- Implemented in the current performance pass.
- Needs follow-up profiling to confirm reduced snapshot/layout work during focus movement and pagination.

## Step 5: Fix Paging Math

Tasks:

- Replace `DefaultPageSize` with `pageSize` in `hasNextPage`.
- Audit and fix `startIndex` for Recently Added and Next Up if they are item offsets.
- Add comments where endpoint-specific paging differs.

Verification:

- Confirm page requests use expected offsets.
- Confirm duplicate items do not appear after paging.

Status:

- Implemented in the current performance pass.
- Needs real-library verification that Next Up page requests use expected offsets and Recently Added does not duplicate or skip items after paging.

## Step 6: Tune Image Request Sizes

Tasks:

- Pass bucketed grid image sizes into `PosterImage`.
- Keep row image sizes unchanged unless separate profiling shows row image pressure.

Verification:

- Compare visual quality on a 4K Apple TV.
- Compare Time Profiler and memory behavior during fast scrolling.

Status:

- Not started.

## Step 7: Preload Upcoming Page and Image Work

Tasks:

- Add profiling markers or logging around next-page request start, response, `elements.append`, snapshot apply, cell configuration, and image load start.
- Decide whether to tune `pagingPrefetchRows`, `pageSize`, image preheating, or buffered page insertion based on those timings.
- If image work dominates, preheat upcoming poster URLs with Nuke using bounded row windows and bucketed request widths.

Verification:

- Capture another device profile while scrolling until pagination triggers.
- Confirm the row-load hitch moves earlier, shrinks, or disappears.
- Confirm cache/memory/network behavior remains reasonable.

Status:

- Implemented in the current performance pass as a 36-item Nuke image preheat window.
- Needs follow-up device profiling to confirm row-load stutters decrease.

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
| After focus reconfiguration fix | 194 over 38.57 s | 320 ms | 3 | up to 294 passes | Cell rebuilds were improved, but glass/offscreen work remained high |
| After focused-only glass, first attempt | 48 over 16.89 s | 219.99 ms | 0 | up to 232 passes | Glass labels dropped substantially, but SwiftUI animation broke |
| After glass overlay attempt | 62 over 18.57 s | 280 ms | 1 | up to 232 passes | Some animation returned, but clear glass overlay dark-blurred posters |
| After UIKit focus animation + pagination gate | TBD | TBD | TBD | TBD | Expected better focus animation and less row-load stutter |
| After snapshot/layout caching + paging math | Better, exact count TBD | TBD | TBD | TBD | Overall improved, but visible stutters still occur when new rows load |
| After 36-item image preheat window | TBD | TBD | TBD | TBD | Expected to reduce row-load stutter if poster fetch/decode timing is dominant |

Additional glass update counts from follow-up traces:

| Run | `GlassAppearanceScaleEffect` | `GlassEffectShapeModifier` | `GlassContainerCache.UnwrappedMaterial` | Notes |
| --- | ---: | ---: | ---: | --- |
| Stable hosting, glass still installed broadly | 27,224 | 13,270 | 14,107 | `.identity` glass still produced substantial work |
| Focused-only glass, first attempt | 832 | 425 | 456 | Large reduction, but animation regression |
| Glass overlay attempt | 1,372 | 674 | 624 | Still far below broad glass, but visually wrong due poster blur |

## Success Criteria

The first performance pass is successful when:

- Hitch count is substantially lower than 111 in the same scenario.
- Worst hitch is below 100 ms, with a stretch goal below 50 ms.
- Mid-interaction main-thread microhangs are gone.
- Expensive offscreen-pass reports are rare or absent during focus movement, and row-load offscreen spikes are reduced.
- Focus movement remains visually polished and predictable.
- Focused Liquid Glass remains part of the tvOS visual style.
- Unfocused cells do not instantiate `.glassEffect`.
- Focused posters are not darkened or blurred by a glass overlay.
- Pagination still loads before the user reaches the end.
- New row loads do not cause repeated near-end requests for the same item count.
