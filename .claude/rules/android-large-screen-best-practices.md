---
description: Build Android UI that adapts to tablets, foldables, desktop windows, connected displays, and Googlebook — window size classes, canonical layouts, fold posture, multi-window and multi-instance, desktop windowing, and the Android 16/17 rule that large screens ignore orientation, aspect-ratio, and resizability restrictions
globs: "**/*.{kt,kts,xml}"
paths:
  - "**/*.{kt,kts,xml}"
must:
  - "Branch on window size classes read once at the screen root, never on device type, `isTablet()`, or orientation."
  - "Don't lock orientation or resizability; from targetSdk 37 the opt-out is gone."
  - "Use Material 3 adaptive scaffolds (`NavigationSuiteScaffold`, list-detail) instead of custom breakpoints."
  - "Fold and unfold are configuration changes: keep state in ViewModels and `rememberSaveable`."
---

# Android Large Screens & Foldables

Every Android app already runs on tablets, unfolded foldables, desktop windows, external displays, and Googlebook laptops. The question is whether it *adapts* or just stretches. On screens with smallest width ≥ 600dp the platform now **ignores `screenOrientation`, `resizeableActivity`, `minAspectRatio`, `maxAspectRatio`, and `setRequestedOrientation()`**:

- **Android 16 (targetSdk 36)** introduced it, with a temporary opt-out (`PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY`).
- **Android 17 (targetSdk 37)** removes the opt-out. Locking to portrait no longer works there, so adaptive layout is the only path.
- **Exempt:** games (`android:appCategory="game"`), screens below sw600dp, and users who pick the app's default in the system aspect-ratio settings. Nothing else.

This rule installs when `tablet` is in `--android-platforms` (the default). For a full audit, invoke the **`android-adaptive-layout-pro`** skill.

## Window size classes, not device types

- **Branch on the window, never the device.** `isTablet()`, `smallestScreenWidthDp >= 600`, `SCREENLAYOUT_SIZE_*`, and `Build.MODEL` allowlists break on foldables, multi-window, desktop windows, and a phone driving an external display. Read the size class **once near the screen root** and pass decisions down.
- **Compose:** `currentWindowAdaptiveInfoV2().windowSizeClass` (Material 3 adaptive 1.3+). It replaces `currentWindowAdaptiveInfo()`, which is deprecated, and includes the large and extra-large width classes by default.
- **Views / non-Compose:** `WindowSizeClass.BREAKPOINTS_V2.computeWindowSizeClass(WindowMetricsCalculator.getOrCreate().computeCurrentWindowMetrics(activity))` (WindowManager 1.5).
- **Branch with the breakpoint API:** `windowSizeClass.isWidthAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND)` (also `WIDTH_DP_EXPANDED_LOWER_BOUND`, `WIDTH_DP_LARGE_LOWER_BOUND`, and the `HEIGHT_DP_*` equivalents). `WindowWidthSizeClass` / `WindowHeightSizeClass` enum comparisons are deprecated.
- Breakpoints: **compact** < 600dp, **medium** 600–839dp (tablets portrait, unfolded foldables), **expanded** 840–1199dp, **large** 1200–1599dp, **extra-large** ≥ 1600dp (desktop windows, external monitors).
- Height classes matter too. A landscape phone is *expanded width, compact height*; don't stack tall content there.

## Canonical layouts via Material 3 adaptive

Reach for the scaffolds before hand-rolling `if (expanded) Row else Column`:

- **`NavigationSuiteScaffold`**: picks a bottom bar or a navigation rail from the window size, including at runtime resizes. On desktop widths, Material 3 favors a rail that expands into a navigation panel over a permanent drawer.
- **List-detail**: `NavigableListDetailPaneScaffold` (predictive back built in), or with Navigation 3, `ListDetailSceneStrategy` from `adaptive-navigation3` (`rememberListDetailSceneStrategy()`, entries tagged with `ListDetailSceneStrategy.listPane()` / `detailPane()` metadata). The Navigation 3 strategies are `@ExperimentalMaterial3AdaptiveApi`.
- **Supporting pane**: `SupportingPaneScaffold` or `SupportingPaneSceneStrategy`.
- **Resizable panes**: `Modifier.paneExpansionDraggable` with a drag handle lets users resize the split; it ships with accessibility semantics.
- **Secondary elements don't stretch**: bottom sheets, buttons, and text fields get a max width on large windows; context menus open next to the item; dialogs stay centered.
- Custom layouts: a **max content width** for text (~600–840dp), and `LazyVerticalGrid(GridCells.Adaptive(minSize))` behind feeds.

## Foldables — posture awareness

- **Compose:** `currentWindowAdaptiveInfoV2().windowPosture` gives a `Posture` with `isTabletop` and hinge bounds (`separatingVerticalHingeBounds`, `occludingVerticalHingeBounds`, and the horizontal variants) in window coordinates.
- **Views / lower level:** `WindowInfoTracker.getOrCreate(context).windowLayoutInfo(activity)` and its `FoldingFeature` (`state` `FLAT` / `HALF_OPENED`, `orientation`, `occlusionType`, `isSeparating`). Observe it once at the screen root.
- **Tabletop** (half-opened, horizontal hinge): content on top (video, viewfinder), controls on the bottom half. **Book** (vertical hinge): two panes split at the hinge. Keep controls off separating and occluding hinge bounds.
- Spend posture code where it pays: media, camera, reading. A settings screen needs none.
- **Fold/unfold is a configuration change.** User input, scroll position, selection, and media position survive it (ViewModel + `rememberSaveable`). Don't restart flows on unfold. Inner ↔ outer display switches change the size class mid-session, so never cache an early size decision.

## Multi-window, multi-instance, and desktop windows

Split screen, free-form desktop windowing on tablets, connected external displays, and Googlebook all resize the window at any time and can run several of your windows at once.

- **Multi-resume**: in multi-window, your activity can be resumed but not focused. Keep updating the UI (playback, new messages, progress) and handle losing the camera or microphone to another app.
- **Multi-instance**: if users benefit from two windows (documents, chats), declare `<property android:name="android.window.PROPERTY_SUPPORTS_MULTI_INSTANCE_SYSTEM_UI" android:value="true" />` on `<application>` so the system offers "New window". Keep per-window state in that window's ViewModel, never in a singleton.
- **Desktop caption bar**: every desktop window has a header bar. Pad content with `WindowInsets.captionBar`; to draw into it, set `APPEARANCE_TRANSPARENT_CAPTION_BAR_BACKGROUND`, avoid `WindowInsets.getBoundingRects()` (the system buttons), and claim custom interactive areas with `setSystemGestureExclusionRects()`.
- **Connected displays**: the `Display` and its density change when a window moves between screens. Read window and display info from the **activity context** (or `LocalConfiguration` / `LocalDensity`), never the application context.
- **Desktop vs touch UI**: decide on pointer precision, not device type. WindowManager's `windowEngagementInfo()` (`EngagementMode.PRECISE_POINTER`) and Compose's `mediaQuery { pointerPrecision … }` are both still pre-stable (1.6 alpha / experimental); size classes plus hover and right-click support are the stable baseline.
- **Views apps**: activity embedding (`SplitPairRule`, `ActivityEmbeddingController`) shows two activities side by side; opt in to `EmbeddingConfiguration` auto-save so splits survive process death.

## Manifest & configuration

- **Remove orientation and resizability restrictions** from non-game activities: `android:screenOrientation` portrait/landscape values, `resizeableActivity="false"`, `minAspectRatio`, `maxAspectRatio`, and runtime `setRequestedOrientation()` calls. Large screens ignore them anyway; handle orientation in layout.
- **Delete `PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY`** before targeting API 37. It is ignored there.
- **Window ≠ display.** `Resources.displayMetrics` and `windowManager.defaultDisplay` describe the display; use `WindowMetricsCalculator` / `LocalWindowInfo` / the size class for layout math.
- **Camera**: preview must stay proportioned and upright in both orientations, folded and unfolded, and in multi-window. CameraX's `PreviewView` handles it; hand-rolled Camera2 math that assumes portrait stretches.

## Input on large screens

- **Keyboard**: switch between physical and virtual keyboards without relaunching; Tab and arrow navigation through main flows; Enter sends in messaging, Esc closes dialogs and menus, Space plays/pauses media; common shortcuts (cut/copy/paste/undo) published to the Keyboard Shortcuts Helper (`onProvideKeyboardShortcuts`). Focus semantics live in `android-accessibility-best-practices.md`.
- **Mouse / trackpad**: hover states (`Modifier.hoverable` + indication), right-click → context menu next to the item, scrolling in both directions, contextual pointer icons (`Modifier.pointerHoverIcon`).
- **Stylus**: basic stylus works like touch; Android 14+ supports handwriting in text fields. Drawing apps add pressure/tilt (`PointerType.Stylus`) and low-latency ink (`androidx.ink`).
- **Drag and drop** between windows: `Modifier.dragAndDropSource` / `dragAndDropTarget`, `View.DRAG_FLAG_GLOBAL_SAME_APPLICATION` to drag between your own instances, and `requestDragAndDropPermissions()` before reading dropped content from another app.

## Testing

- **Emulators**: Pixel Fold (fold, unfold, half-open), Medium Tablet, Desktop (Android Studio canary), and the resizable emulator. Enter split-screen and desktop windowing; minimize, maximize, and restore the window.
- **Test the combinations**, not just each change: resize then rotate, rotate then fold, with text typed, a list scrolled, and media playing.
- **Exercise the Android 17 behavior early** with the `UNIVERSAL_RESIZABLE_BY_DEFAULT` compat flag (app compatibility framework) before raising targetSdk.
- **Compose tests**: `DeviceConfigurationOverride.ForcedSize` per size class; screenshot-test each canonical layout at compact, medium, expanded, and large.
- **Play's adaptive app quality tiers**: Tier 3 *Adaptive ready* (no letterboxing, state survives configuration changes, multi-window and multi-resume, camera preview, basic keyboard/mouse/stylus), Tier 2 *Adaptive optimized* (size-class layouts, no stretched secondary elements, keyboard navigation and shortcuts, right-click), Tier 1 *Adaptive differentiated* (multitasking, postures, drag and drop, advanced stylus). Play badges desktop-optimized apps on Googlebook.

## Common Pitfalls

- Device checks (`isTablet()`, `smallestScreenWidthDp`, `Build.MODEL` allowlists) instead of window size classes.
- `currentWindowAdaptiveInfo()` (deprecated) or `WindowWidthSizeClass` comparisons; re-reading the size class in every composable.
- Orientation locks, `resizeableActivity="false"`, aspect-ratio limits, or the Android 16 opt-out kept as a strategy. All ignored on large screens at targetSdk 37.
- Text, buttons, and bottom sheets stretched to 1200dp; a phone layout made wider.
- State in `remember` lost on fold, resize, or a move to another display.
- Bottom navigation bar on a 13" tablet (use `NavigationSuiteScaffold`).
- Application-context display metrics on a connected display.
- Content under the desktop caption bar, or custom header controls with no gesture exclusion.
- Pausing everything in `onPause` in multi-window; singletons holding per-window state.
- Camera preview stretched because orientation was assumed portrait.
