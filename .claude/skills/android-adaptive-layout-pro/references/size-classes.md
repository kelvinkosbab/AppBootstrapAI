# Window size classes and canonical layouts

The adaptation unit is the **window**: on a foldable it changes when the device unfolds, in multi-window it changes when the divider moves, on desktop it changes when the user resizes. Anything keyed off the *device* is wrong in at least one of those.

## Reading the size class

- **API**: `currentWindowAdaptiveInfoV2().windowSizeClass` (Material 3 adaptive 1.3+) or `WindowSizeClass.BREAKPOINTS_V2.computeWindowSizeClass(windowMetrics)` (WindowManager 1.5, with `WindowMetricsCalculator.getOrCreate().computeCurrentWindowMetrics(activity)`). Branch with `isWidthAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND)` / `WIDTH_DP_EXPANDED_LOWER_BOUND` / `WIDTH_DP_LARGE_LOWER_BOUND` and the height equivalents.
- **Deprecated**: `WindowWidthSizeClass.COMPACT/MEDIUM/EXPANDED` equality checks (pre-1.4 enum style), and `currentWindowAdaptiveInfo()` (deprecated in Material 3 adaptive 1.3; its `supportLargeAndXLargeWidth` parameter defaults to `false`, so it silently ignores large and extra-large). Flag both and migrate to `currentWindowAdaptiveInfoV2()` and the breakpoint API.
- **`BREAKPOINTS_V2`** adds large (≥ 1200dp) and extra-large (≥ 1600dp). `currentWindowAdaptiveInfoV2()` uses them by default; WindowManager callers must pass `BREAKPOINTS_V2` explicitly. Desktop windows, connected displays, and Googlebook routinely reach these widths, so a 1600dp window must not get the 840dp layout stretched.
- **Where**: once, near the screen root (the `NavHost` destination or screen composable); pass a small decision object down (`twoPane: Boolean`, `navType: NavType`). Findings: re-reading in leaf composables (recomposition churn + inconsistent decisions) and reading `LocalConfiguration.current.screenWidthDp` instead (that's the *display* in some configurations, and it lacks height classes).
- **Height is a class too**: landscape phones are expanded-width / compact-height. A layout branching only on width will stack a tall detail pane into 360dp of height.

## Heuristics to flag

- `isTablet()`, `smallestScreenWidthDp >= 600`, `Configuration.SCREENLAYOUT_SIZE_*`, `resources.getBoolean(R.bool.isTablet)` / `values-sw600dp` qualifiers driving *layout structure* (qualifiers for dimension tokens are fine; for which-layout-to-show they miss multi-window and foldables).
- `Build.MODEL` allowlists or built-in display size checks for large-screen features. A phone driving an external monitor keeps its model name and built-in display, so these never fire there.
- `LocalConfiguration.current.orientation` to choose between layouts — orientation is a consequence of window shape; branch on the size class.

## Canonical layouts

Material 3 adaptive ships the three canonical layouts; prefer them over hand-rolled conditionals because they handle runtime resize and back navigation:

- **Navigation**: `NavigationSuiteScaffold` — bottom bar (compact) → rail (medium) → permanent drawer (expanded). A `NavigationBar` rendered unconditionally is a degraded-tier finding on tablets.
- **List-detail**: `ListDetailPaneScaffold` / `NavigableListDetailPaneScaffold` — two panes on expanded, single pane below, predictive back handled. Flag custom two-pane code that loses the detail selection on resize.
- **Navigation 3 apps**: `ListDetailSceneStrategy` / `SupportingPaneSceneStrategy` from `androidx.compose.material3.adaptive:adaptive-navigation3` (1.3, `@ExperimentalMaterial3AdaptiveApi`) arrange back-stack entries into panes from `NavEntry` metadata (`ListDetailSceneStrategy.listPane()`, `detailPane()`, `extraPane()`), passed to `NavDisplay(sceneStrategies = listOf(strategy))`. In a Navigation 3 app, prefer these over wrapping a scaffold by hand.
- **Pane adaptation (1.2+)**: reflow and levitate adapt strategies move a pane under another or float it as a popup when space runs out; `Modifier.paneExpansionDraggable` plus a drag handle lets users resize the split. Use them before custom show/hide logic.
- **Supporting pane**: `SupportingPaneScaffold` for primary + auxiliary content (filters, metadata, comments).
- **Feed**: `LazyVerticalGrid(GridCells.Adaptive(minSize = 240.dp))` rather than a `LazyColumn` that becomes a 1200dp-wide single column.

## Content width and density

- **Max content width** on expanded: readable measure is ~600–840dp; text stretched edge to edge on a 13" tablet is a degraded finding. Center with `widthIn(max = …)` or use pane scaffolds.
- **Touch targets stay 48dp** but *spacing* can grow on expanded; density doesn't change, so don't shrink controls because "there's more room."
- Dialogs/sheets: full-screen modal bottom sheets on a tablet are a phone idiom — `AlertDialog`/centered dialogs or a supporting pane on expanded.
- Secondary elements (Play Tier 2 `UI_Secondary_Elements`): bottom sheets, buttons, and text fields get a max width on large screens; context menus open next to the selected item; small edit menus don't cover the screen.

## Audit sequence

1. Grep for device heuristics (`isTablet`, `smallestScreenWidthDp`, `SCREENLAYOUT_SIZE`, `orientation ==`, `Build.MODEL`).
2. Locate every `currentWindowAdaptiveInfo()` / `currentWindowAdaptiveInfoV2()` / `computeWindowSizeClass()` call — count, placement, and whether large/extra-large are included.
3. For each screen: which canonical layout does it want, and does it use the scaffold or hand-roll it?
4. Check the three navigation components appear per class (not a bottom bar everywhere).
5. Check expanded-width text/content width.
