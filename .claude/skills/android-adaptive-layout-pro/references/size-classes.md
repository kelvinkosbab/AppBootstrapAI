# Window size classes and canonical layouts

The adaptation unit is the **window**: on a foldable it changes when the device unfolds, in multi-window it changes when the divider moves, on desktop it changes when the user resizes. Anything keyed off the *device* is wrong in at least one of those.

## Reading the size class

- **API**: `currentWindowAdaptiveInfo().windowSizeClass` (Material 3 adaptive) or `computeWindowSizeClass()` (WindowManager). Branch with `isWidthAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND)` / `WIDTH_DP_EXPANDED_LOWER_BOUND` and the height equivalents.
- **Deprecated**: `WindowWidthSizeClass.COMPACT/MEDIUM/EXPANDED` equality checks (pre-1.4 enum style) — flag and migrate to the breakpoint API.
- **`BREAKPOINTS_V2`** adds large (≥ 1200dp) and extra-large (≥ 1600dp); apps that show on desktop/connected displays should opt in so 1600dp windows don't get the 840dp layout stretched.
- **Where**: once, near the screen root (the `NavHost` destination or screen composable); pass a small decision object down (`twoPane: Boolean`, `navType: NavType`). Findings: re-reading in leaf composables (recomposition churn + inconsistent decisions) and reading `LocalConfiguration.current.screenWidthDp` instead (that's the *display* in some configurations, and it lacks height classes).
- **Height is a class too**: landscape phones are expanded-width / compact-height. A layout branching only on width will stack a tall detail pane into 360dp of height.

## Heuristics to flag

- `isTablet()`, `smallestScreenWidthDp >= 600`, `Configuration.SCREENLAYOUT_SIZE_*`, `resources.getBoolean(R.bool.isTablet)` / `values-sw600dp` qualifiers driving *layout structure* (qualifiers for dimension tokens are fine; for which-layout-to-show they miss multi-window and foldables).
- `LocalConfiguration.current.orientation` to choose between layouts — orientation is a consequence of window shape; branch on the size class.

## Canonical layouts

Material 3 adaptive ships the three canonical layouts; prefer them over hand-rolled conditionals because they handle runtime resize and back navigation:

- **Navigation**: `NavigationSuiteScaffold` — bottom bar (compact) → rail (medium) → permanent drawer (expanded). A `NavigationBar` rendered unconditionally is a degraded-tier finding on tablets.
- **List-detail**: `ListDetailPaneScaffold` / `NavigableListDetailPaneScaffold` — two panes on expanded, single pane below, back handled. Flag custom two-pane code that loses the detail selection on resize.
- **Supporting pane**: `SupportingPaneScaffold` for primary + auxiliary content (filters, metadata, comments).
- **Feed**: `LazyVerticalGrid(GridCells.Adaptive(minSize = 240.dp))` rather than a `LazyColumn` that becomes a 1200dp-wide single column.

## Content width and density

- **Max content width** on expanded: readable measure is ~600–840dp; text stretched edge to edge on a 13" tablet is a degraded finding. Center with `widthIn(max = …)` or use pane scaffolds.
- **Touch targets stay 48dp** but *spacing* can grow on expanded; density doesn't change, so don't shrink controls because "there's more room."
- Dialogs/sheets: full-screen modal bottom sheets on a tablet are a phone idiom — `AlertDialog`/centered dialogs or a supporting pane on expanded.

## Audit sequence

1. Grep for device heuristics (`isTablet`, `smallestScreenWidthDp`, `SCREENLAYOUT_SIZE`, `orientation ==`).
2. Locate every `currentWindowAdaptiveInfo()` / `computeWindowSizeClass()` call — count and placement.
3. For each screen: which canonical layout does it want, and does it use the scaffold or hand-roll it?
4. Check the three navigation components appear per class (not a bottom bar everywhere).
5. Check expanded-width text/content width.
