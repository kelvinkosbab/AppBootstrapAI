---
description: Build Android UI that adapts to tablets, foldables, and desktop windows — window size classes, canonical layouts, fold posture, and the Android 16 rule that large screens ignore orientation and resizability restrictions
globs: "**/*.{kt,kts,xml}"
---

# Android Large Screens & Foldables

Every Android app already runs on tablets, unfolded foldables, Chromebooks, and desktop windows — the question is whether it *adapts* or just stretches. Since **Android 16 (targetSdk 36), the platform ignores `screenOrientation`, aspect-ratio, and `resizeableActivity` restrictions on screens ≥ 600dp** — locking to portrait no longer works there, so adaptive layout is the only path. This rule installs when `tablet` is in `--android-platforms` (the default).

## Window size classes, not device types

- **Branch on the window, never the device.** `isTablet()` heuristics break on foldables, multi-window, and desktop windows. Read `currentWindowAdaptiveInfo().windowSizeClass` **once near the screen root** and pass decisions down — don't re-query in leaf composables.
- **Use the breakpoint API** (WindowManager 1.4+): `windowSizeClass.isWidthAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND)` / `WIDTH_DP_EXPANDED_LOWER_BOUND`. The older `WindowWidthSizeClass.COMPACT/MEDIUM/EXPANDED` enum comparisons are deprecated.
- Breakpoints: **compact** < 600dp (phones portrait), **medium** 600–839dp (tablets portrait, unfolded foldables), **expanded** ≥ 840dp (tablets landscape, desktop); `WindowSizeClass.BREAKPOINTS_V2` adds **large** ≥ 1200dp and **extra-large** ≥ 1600dp for desktop windows.
- Height classes matter too — a landscape phone is *expanded width, compact height*; don't stack tall content there.

## Canonical layouts via Material 3 adaptive

Reach for the scaffolds before hand-rolling `if (expanded) Row else Column`:

- **`NavigationSuiteScaffold`** — bottom bar on compact, navigation rail on medium, drawer on expanded. Automatic, including at runtime resizes.
- **`ListDetailPaneScaffold`** / **`NavigableListDetailPaneScaffold`** — list + detail side by side on expanded, single pane otherwise, with back-navigation handled.
- **`SupportingPaneScaffold`** — primary content + supporting pane (filters, metadata).
- Custom layouts: enforce a **max content width** on expanded (readable line length ~600–840dp) instead of stretching text edge to edge; put `LazyVerticalGrid(GridCells.Adaptive(minSize))` behind feeds.

## Foldables — posture awareness

- Observe `WindowInfoTracker.getOrCreate(context).windowLayoutInfo(activity)` and look for a `FoldingFeature`: `state` (`FLAT` / `HALF_OPENED`), `orientation`, `occlusionType`, `isSeparating`. Expose it as state from the screen root, like the size class.
- **Tabletop posture** (half-opened, horizontal hinge): move controls to the bottom half and content to the top (video, camera viewfinder). **Book posture** (vertical hinge): two-pane layouts split at the hinge; keep controls off `occlusionType == FULL` regions.
- **Fold/unfold is a configuration change** — state must survive it: ViewModel + `rememberSaveable`, never `remember` alone for user input or scroll position. Don't restart flows on unfold.
- Inner vs outer display switch changes the size class mid-session — the root `windowSizeClass` read handles it; cached device-type decisions don't.

## Manifest & configuration

- **Remove `android:screenOrientation="portrait"`** and `resizeableActivity="false"` from activities — ignored on large screens since Android 16 anyway, and they break multi-window. Handle orientation in layout, not by forbidding it.
- The Android 16 opt-out (`PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY`) is temporary and removed at targetSdk 37 — don't ship it as a strategy.
- Support multi-window and free-form resize: no assumptions that the window equals the display (`Resources.displayMetrics` is the display, `LocalConfiguration`/`windowSizeClass` is the window).
- Camera apps: preview orientation must follow `Display.rotation` and the window, not the sensor default — the classic stretched-preview bug on tablets.

## Input on large screens

- Tablets and desktop windows bring **keyboards, mice, trackpads, and styluses**: hover states on interactive elements (`Modifier.hoverable` / `indication`), keyboard focus visibility and shortcuts (see `android-accessibility-best-practices.md` — the keyboard work serves both audiences), right-click → context menu, stylus input with `Modifier.pointerInput` + `PointerType.Stylus` where it matters.
- **Drag and drop** between apps is expected in multi-window — `Modifier.dragAndDropSource/Target` for content users would naturally drag (images, text, files).

## Testing

- Run on the **Pixel Tablet and Pixel Fold AVDs** and the **resizable emulator**; rotate, fold/unfold, enter split-screen. Desktop mode on a Chromebook or Android 16 connected display for free-form windows.
- Compose tests: `DeviceConfigurationOverride.ForcedSize` / `.WindowInsets` to exercise each size class headlessly; screenshot-test each canonical layout at compact/medium/expanded.
- Verify against **Play's large-screen quality tiers** before listing; Play surfaces tablet quality in the store.

## Common Pitfalls

- `isTablet()` / `smallestScreenWidthDp >= 600` device checks instead of window size classes.
- Re-reading `currentWindowAdaptiveInfo()` in every composable — branch at the root, pass down.
- Orientation locks as a "solution" — silently ignored on large screens since Android 16.
- Text stretched to 1200dp lines; a single `Column` that is just a phone layout made wider.
- State in `remember` lost on fold/unfold; scroll position reset on rotation.
- Bottom navigation bar on a 13" tablet (use `NavigationSuiteScaffold`).
- Camera preview stretched because orientation was assumed portrait.
