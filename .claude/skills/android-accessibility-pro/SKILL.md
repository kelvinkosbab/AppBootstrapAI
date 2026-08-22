---
name: android-accessibility-pro
description: Deep-reviews Android app accessibility — the TalkBack semantics tree (content descriptions, roles, merging, state, custom actions, live regions), Bluetooth assistive input (external keyboards, Switch Access, braille displays), and visual accessibility (contrast, dynamic text, color-independence, reduce motion). Use when auditing Compose screens for accessibility, preparing the Play listing's accessibility answers, or when reading, writing, or reviewing accessibility code.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "Android Developers accessibility docs (Compose semantics), WCAG 2.2 AA, TalkBack 15+ / Android 15-16 behavior (HID braille, announceForAccessibility deprecation)"
---

Review Android app accessibility for correctness and completeness. This is the deep-review companion to the always-on `android-accessibility-best-practices.md` rule — the rule steers while writing; this skill audits whole screens. The Android sibling of `swift-accessibility-pro`. Report only genuine problems; don't nitpick.

Applies to Jetpack Compose (primary) with View-interop notes. If asked to **write or fix** rather than review, make the changes directly and summarize them in the same file-by-file format.

Review process:

1. Audit the TalkBack semantics tree using `references/semantics.md` — content descriptions, roles, merging, state descriptions, custom actions, live regions, and the deprecated-announcement migration.
2. Audit Bluetooth assistive input using `references/input-access.md` — keyboard/D-pad reachability, Switch Access scanning, braille-display label quality.
3. Audit visual accessibility using `references/visual.md` — contrast, dynamic text scaling, touch targets, color-independence, reduce motion.

If doing a partial review, load only the relevant reference files.

## Core Instructions

- **Audit the semantics tree, not the code style.** The question for every Composable is what TalkBack/keyboard/braille users actually receive — trace `semantics` modifiers to the resulting node, don't assume.
- **The input methods share one tree.** A `CustomAccessibilityAction` serves TalkBack's action menu, Switch Access, AND braille users; a missing one fails all three. Report tree problems once, noting every affected input method.
- **Flag deprecated announcement APIs on sight**: `announceForAccessibility()` / `TYPE_ANNOUNCEMENT` (deprecated Android 16) → `liveRegion` / `paneTitle` / `stateDescription` semantics. AI-generated code still emits the old calls.
- **Localization is part of accessibility.** Hardcoded strings in `contentDescription`, `stateDescription`, or action labels are findings — everything routes through `stringResource(...)`.
- **Severity by user impact**: task-blocking (unreachable control, missing label on a primary action, focus trap) > degraded (fragmented rows, sub-48dp targets, contrast near-misses) > polish (verbosity tuning).
- **Name the verification path** where relevant: Compose semantics tests (`onNodeWithContentDescription`), the Accessibility Scanner app, TalkBack on device, or a paired Bluetooth keyboard.
- Never suggest suppressing or hollowing out an accessibility affordance to silence a finding.

## Output Format

Organize findings by file. For each issue: file/line, the violated principle, affected assistive tech (TalkBack / keyboard / switch / braille / low-vision), and a brief before/after. Skip clean files. End with a prioritized summary, task-blocking issues first.

Example finding:

### FeedRow.kt

**Line 18: icon + two texts exposed as three TalkBack nodes — fragmented reading; Switch Access scans three stops per row.**

```kotlin
// Before
Row(modifier = Modifier.clickable(onClick = onOpen)) {
    Icon(Icons.Default.Wifi, contentDescription = stringResource(R.string.wifi))
    Column { Text(item.title); Text(item.subtitle) }
}

// After — one merged node; icon is decorative (text carries the meaning)
Row(
    modifier = Modifier
        .clickable(onClick = onOpen)
        .semantics(mergeDescendants = true) { }
) {
    Icon(Icons.Default.Wifi, contentDescription = null)
    Column { Text(item.title); Text(item.subtitle) }
}
```

### Summary

1. **Task-blocking:** `pointerInput`-only card in `ScanScreen.kt` unreachable by keyboard/Switch Access — use `clickable` or add `focusable()` + semantics `onClick`.
2. **Degraded:** 4 fragmented rows; error snackbar uses deprecated `announceForAccessibility`.
3. **Polish:** emoji in `stateDescription` renders as braille noise.

End of example.

## References

- `references/semantics.md` — the TalkBack tree: description/role/state audit, merging, custom actions, live regions, pane titles, the announcement migration, View-interop notes.
- `references/input-access.md` — Bluetooth keyboards, Switch Access, and braille displays: focusability, scan order, label quality.
- `references/visual.md` — contrast and how to check it, sp-based text scaling, 48dp targets, color-independence, reduce motion.
