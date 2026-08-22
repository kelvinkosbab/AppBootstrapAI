---
name: android-adaptive-layout-pro
description: Deep-reviews Android apps for tablet, foldable, and desktop-window readiness — window size class usage, canonical layouts (Material 3 adaptive scaffolds), fold posture handling, state survival across fold/unfold and resize, manifest orientation/resizability restrictions (ignored on large screens since Android 16), and large-screen input (keyboard, mouse, stylus, drag-and-drop). Use when making an app large-screen ready, auditing against Play's large-screen quality tiers, or when reading, writing, or reviewing adaptive layout code.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "Android Developers adaptive-apps guides, Jetpack WindowManager 1.5, Material 3 adaptive 1.x, Android 16 behavior changes (orientation/resizability restrictions ignored on large screens)"
---

Review Android code for large-screen and foldable readiness. This is the deep-review companion to the always-on `android-large-screen-best-practices.md` rule — the rule steers while writing; this skill audits whole screens and the manifest. Report only genuine problems; don't nitpick.

Applies to Jetpack Compose apps (with View-interop notes). If asked to **write or fix** rather than review, make the changes directly and summarize them in the same file-by-file format.

Review process:

1. Audit how layouts branch using `references/size-classes.md` — window size class reads, breakpoint API, canonical layouts vs hand-rolled conditionals, content width, navigation components per class.
2. Audit foldable behavior using `references/foldables.md` — posture handling, `FoldingFeature` observation, state survival across fold/unfold and display switches.
3. Audit configuration, input, and testing using `references/quality-checklist.md` — manifest restrictions (Android 16), multi-window assumptions, camera orientation, keyboard/mouse/stylus/drag-and-drop, Play quality-tier readiness, test coverage per size class.

If doing a partial review, load only the relevant reference files.

## Core Instructions

- **The unit of adaptation is the window, not the device.** Any device-type heuristic (`isTablet`, `smallestScreenWidthDp`) is a finding regardless of how well it happens to work today — foldables and multi-window break it.
- **Assume Android 16 behavior.** Orientation/aspect-ratio/resizability restrictions are ignored on ≥ 600dp screens for targetSdk 36+; a locked portrait layout is a *bug waiting to ship*, not a deliberate constraint. Flag the restriction AND the layout that depended on it.
- **Fold/unfold and resize are configuration changes.** Trace what happens to user input, scroll position, selection, and in-flight work — state in plain `remember` or Activity fields is a finding.
- **Prefer the scaffolds.** Hand-rolled `if (expanded) Row else Column` trees aren't wrong, but when a Material 3 adaptive scaffold fits (navigation suite, list-detail, supporting pane), recommend it — it handles runtime resizes and back navigation the custom code usually forgets.
- **Severity by user impact**: broken (stretched/unusable layout, state loss on fold, camera preview wrong) > degraded (phone layout made wider, bottom bar on a 13" screen, no hover/keyboard support) > polish (missing large/extra-large tuning).
- Cross-reference, don't duplicate: keyboard focus and a11y semantics belong to `android-accessibility-pro`; recomposition cost to `android-compose-pro`.

## Output Format

Organize findings by file. For each issue: file/line, the violated principle, the form factor(s) affected (tablet / foldable / desktop window / multi-window), and a brief before/after. Skip clean files. End with a prioritized summary, broken-tier issues first.

Example finding:

### FeedScreen.kt

**Line 22: device-type heuristic drives the layout — wrong in multi-window and on foldables.**

```kotlin
// Before
val isTablet = LocalConfiguration.current.smallestScreenWidthDp >= 600
if (isTablet) TwoPane() else SinglePane()

// After — branch on the window, once, at the root
val sizeClass = currentWindowAdaptiveInfo().windowSizeClass
val twoPane = sizeClass.isWidthAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_EXPANDED_LOWER_BOUND)
if (twoPane) TwoPane() else SinglePane()
```

### Summary

1. **Broken:** `android:screenOrientation="portrait"` on `MainActivity` — ignored on large screens since Android 16; the portrait-only feed layout stretches on tablets.
2. **Degraded:** bottom `NavigationBar` at all sizes — adopt `NavigationSuiteScaffold`; 3 device-type heuristics.
3. **Polish:** no hover states on feed cards for mouse/trackpad users.

End of example.

## References

- `references/size-classes.md` — window size classes and the breakpoint API, where to read them, canonical layouts and the M3 adaptive scaffolds, content width, per-class navigation.
- `references/foldables.md` — `FoldingFeature` posture handling (tabletop/book), inner/outer display switches, state survival across fold/unfold.
- `references/quality-checklist.md` — manifest restrictions and the Android 16 change, multi-window assumptions, camera orientation, keyboard/mouse/stylus/drag-and-drop, Play large-screen quality tiers, testing per size class.
