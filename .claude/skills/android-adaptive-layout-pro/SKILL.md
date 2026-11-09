---
name: android-adaptive-layout-pro
description: Deep-reviews Android apps for tablet, foldable, desktop-window, connected-display, and Googlebook readiness — window size class usage, canonical layouts (Material 3 adaptive scaffolds and Navigation 3 scene strategies), fold posture handling, state survival across fold/unfold and resize, manifest orientation/aspect-ratio/resizability restrictions (ignored on large screens since Android 16, no opt-out at Android 17), multi-window, multi-instance, and desktop windowing, and large-screen input (keyboard, mouse, stylus, drag-and-drop). Use when making an app large-screen ready, auditing against Play's adaptive app quality tiers, or when reading, writing, or reviewing adaptive layout code.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.1"
  grounded_in: "Android Developers adaptive-apps guides (desktop windowing, connected displays, Googlebook), adaptive app quality guidelines (Tiers 3–1), Jetpack WindowManager 1.5 (1.6 alpha noted), Compose Material 3 adaptive 1.3, Android 16 and Android 17 behavior changes (orientation/aspect-ratio/resizability restrictions ignored on large screens; opt-out removed at API 37)"
---

Review Android code for large-screen and foldable readiness. This is the deep-review companion to the always-on `android-large-screen-best-practices.md` rule — the rule steers while writing; this skill audits whole screens and the manifest. Report only genuine problems; don't nitpick.

Applies to Jetpack Compose apps (with View-interop notes). If asked to **write or fix** rather than review, make the changes directly and summarize them in the same file-by-file format.

Review process:

1. Audit how layouts branch using `references/size-classes.md` — window size class reads, breakpoint API, canonical layouts vs hand-rolled conditionals, content width, navigation components per class.
2. Audit foldable behavior using `references/foldables.md` — posture handling, `FoldingFeature` observation, state survival across fold/unfold and display switches.
3. Audit windowing using `references/multi-window-and-desktop.md` — multi-resume, multi-instance, desktop caption bar, connected displays, activity embedding for View-based apps.
4. Audit configuration, input, and testing using `references/quality-checklist.md` — manifest restrictions (Android 16 and 17), window-vs-display math, camera orientation, keyboard/mouse/stylus/drag-and-drop, Play quality-tier readiness, test coverage per size class.

If doing a partial review, load only the relevant reference files.

**Official companion:** when Google's Android skills ([android/skills](https://github.com/android/skills), Apache-2.0) are installed, see `adaptive`, which builds responsive layouts for window sizes and input methods. Use it when writing new adaptive UI; use this skill to audit an existing app against the quality tiers.

## Core Instructions

- **The unit of adaptation is the window, not the device.** Any device-type heuristic (`isTablet`, `smallestScreenWidthDp`) is a finding regardless of how well it happens to work today — foldables and multi-window break it.
- **Assume Android 17 behavior.** Orientation, aspect-ratio, and resizability restrictions (manifest and `setRequestedOrientation()`) are ignored on ≥ 600dp screens from targetSdk 36, and the temporary opt-out stops working at targetSdk 37. Only games (`android:appCategory="game"`) are exempt. A locked portrait layout is a *bug waiting to ship*, not a deliberate constraint. Flag the restriction AND the layout that depended on it.
- **One app, many windows.** Desktop windowing, connected displays, and Googlebook run several windows of one app side by side and move them between displays. Singletons holding per-window state, application-context display reads, and UI that pauses whenever the activity loses focus are findings.
- **Fold/unfold and resize are configuration changes.** Trace what happens to user input, scroll position, selection, and in-flight work — state in plain `remember` or Activity fields is a finding.
- **Prefer the scaffolds.** Hand-rolled `if (expanded) Row else Column` trees aren't wrong, but when a Material 3 adaptive scaffold fits (navigation suite, list-detail, supporting pane), recommend it — it handles runtime resizes and back navigation the custom code usually forgets.
- **Severity by user impact**: broken (stretched/unusable layout, state loss on fold, camera preview wrong) > degraded (phone layout made wider, bottom bar on a 13" screen, no hover/keyboard support) > polish (missing large/extra-large tuning).
- Cross-reference, don't duplicate: keyboard focus and a11y semantics belong to `android-accessibility-pro`; recomposition cost to `android-compose-pro`.

## Output Format

Organize findings by file. For each issue: file/line, the violated principle, the form factor(s) affected (tablet / foldable / desktop window / connected display / multi-window), and a brief before/after. Skip clean files. End with a prioritized summary, broken-tier issues first.

Example finding:

### FeedScreen.kt

**Line 22: device-type heuristic drives the layout — wrong in multi-window and on foldables.**

```kotlin
// Before
val isTablet = LocalConfiguration.current.smallestScreenWidthDp >= 600
if (isTablet) TwoPane() else SinglePane()

// After — branch on the window, once, at the root
val sizeClass = currentWindowAdaptiveInfoV2().windowSizeClass
val twoPane = sizeClass.isWidthAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_EXPANDED_LOWER_BOUND)
if (twoPane) TwoPane() else SinglePane()
```

### Summary

1. **Broken:** `android:screenOrientation="portrait"` on `MainActivity` — ignored on large screens since Android 16 (no opt-out at targetSdk 37); the portrait-only feed layout stretches on tablets.
2. **Degraded:** bottom `NavigationBar` at all sizes — adopt `NavigationSuiteScaffold`; 3 device-type heuristics.
3. **Polish:** no hover states on feed cards for mouse/trackpad users.

End of example.

## References

- `references/size-classes.md` — window size classes and the breakpoint API, where to read them, canonical layouts and the M3 adaptive scaffolds, content width, per-class navigation.
- `references/foldables.md` — `FoldingFeature` posture handling (tabletop/book), inner/outer display switches, state survival across fold/unfold.
- `references/multi-window-and-desktop.md` — multi-resume, multi-instance, desktop windowing and the caption bar, connected displays, Googlebook, activity embedding.
- `references/quality-checklist.md` — manifest restrictions and the Android 16/17 changes, window-vs-display math, camera orientation, keyboard/mouse/stylus/drag-and-drop, Play adaptive app quality tiers, testing per size class.
