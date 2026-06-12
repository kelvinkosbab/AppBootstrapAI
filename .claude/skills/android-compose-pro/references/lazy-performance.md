# Lazy layout performance

`LazyColumn`/`LazyRow`/`LazyVerticalGrid` jank traces to a short list of mechanisms. Identify the mechanism; don't hand-wave "optimize the list."

## Keys — identity across data changes

```kotlin
LazyColumn {
    items(feed, key = { it.id }) { item -> FeedRow(item) }
}
```

- **Missing `key`**: position is the identity. Any insert/remove/reorder re-binds every item below the change, kills item animations, and mis-attributes `rememberSaveable`/scroll state to wrong rows. This is the single highest-value lazy finding.
- Keys must be **stable and unique** (a database id, not the index, not `hashCode()` of a mutable object). Duplicate keys crash at runtime.
- With keys present, `Modifier.animateItem()` gets reorder/insert animations nearly for free — worth suggesting where lists visibly shuffle.

## `contentType` — recycling across templates

Heterogeneous lists (header / item / ad / footer) should declare `contentType` so the lazy layout reuses compositions within each template:

```kotlin
items(rows, key = { it.id }, contentType = { it.viewType }) { ... }
```

Without it, a header composition gets discarded rather than reused for the next header. Matters at scale (long mixed feeds); noise for a 5-row settings list — calibrate.

## Item lambda hygiene

- Per-item allocations/formatting in the item lambda multiply by visible-item count × recomposition count. Date formatting, `filter`/`map`, image-transform setup → precompute in the ViewModel onto the UI model.
- Item composables should take narrow, stable parameters — an item taking the whole `UiState` recomposes every visible row when anything in the state changes.
- `remember {}` inside `items {}` is per-item-slot and evicted with the item; fine for ephemera, wrong for anything that must survive scrolling away (hoist or use `rememberSaveable` with the item key).

## Scroll-driven state — `derivedStateOf` + `snapshotFlow`

```kotlin
// Recomposing only when the THRESHOLD flips, not every scroll pixel:
val showFab by remember {
    derivedStateOf { listState.firstVisibleItemIndex > 3 }
}
```

Reading `listState.firstVisibleItemIndex`/`scrollOffset` directly in composition recomposes per frame while scrolling — the classic scroll-jank source. Threshold reads go through `derivedStateOf`; side-effecting reactions (analytics, pagination triggers) go through `snapshotFlow { ... }.distinctUntilChanged()` in a `LaunchedEffect`.

## Structural traps

- **Unbounded child in scrollable parent**: `LazyColumn` inside `Column(Modifier.verticalScroll(...))` (or a lazy list inside another same-direction lazy list) gets infinite height — crash or full eager composition. Restructure into ONE `LazyColumn` using `item {}` for the former siblings.
- **Whole-list state replacement**: emitting a brand-new list for a one-item change is fine *with keys* (diffing matches identity) but combined with missing keys it's the worst case. Check the pair together.
- **`fillParentMaxSize` misuse** inside items for "spacer" hacks — usually layout debt.

## Measurement before micro-optimization

Order of evidence: Layout Inspector recomposition counts → frame timing (`Macrobenchmark`/Perfetto) → then code changes. For first-scroll jank specifically, note **Baseline Profiles** (`androidx.baselineprofile`) — JIT cost, not composition cost, and no amount of key-fixing addresses it. Suggest a profile when the symptom is cold-start/first-scroll only.
