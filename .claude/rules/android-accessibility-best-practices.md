---
description: Enforce Android accessibility best practices for TalkBack, Compose semantics, touch targets, dynamic text, and contrast
globs: "**/*.{kt,kts}"
---

# Android Accessibility Best Practices

All Composables must be fully accessible. TalkBack, dynamic text scaling, and sufficient touch targets are required, not optional.

## Content Descriptions

- Every meaningful `Image`, `Icon`, and `IconButton` must set `contentDescription` — use a `stringResource()`, never a hardcoded string.
- Purely decorative images (gradients, dividers, icons next to already-described text) must pass `contentDescription = null`, not an empty string.
- When an icon and text represent the same action, mark the icon `contentDescription = null` and let the text carry the label.

## Compose Semantics

- Use `Modifier.semantics { }` to add or override TalkBack metadata — `contentDescription`, `stateDescription`, `role`, custom actions.
- Merge compound elements (icon + title + subtitle rows) with `Modifier.semantics(mergeDescendants = true) { }` so TalkBack reads them as a single node.
- Mark section titles with `Modifier.semantics { heading() }` so TalkBack users can navigate by heading via the reading-controls rotor.
- Set `Role.Button` / `Role.Checkbox` / `Role.Switch` when custom Composables mimic those controls — `Modifier.semantics { role = Role.Button }`.
- Use `stateDescription` (not `contentDescription`) for values that change — e.g., toggle state, progress, selection.

## Touch Targets

- Minimum touch target is **48dp × 48dp** (Material accessibility guideline). Use `Modifier.minimumInteractiveComponentSize()` or size modifiers to enforce it.
- Never shrink `IconButton` or `Checkbox` below default size without restoring the target with padding.

## Dynamic Text

- Declare text sizes in `sp`, never `dp`, so they respect the user's system font-scale setting.
- Avoid `maxLines = 1` with `TextOverflow.Ellipsis` on critical content unless the full text is also exposed via `contentDescription` or `semantics { text = ... }`.
- Test at Settings → Display → Font size → Largest. Layouts must not truncate required controls.

## Custom Actions

- Items with long-press / swipe / context actions must expose the same options via `Modifier.semantics { customActions = listOf(CustomAccessibilityAction(...)) }`. Gesture-only affordances are invisible to TalkBack.

## Reduce Motion

- Respect the system "Remove animations" setting by checking `LocalAccessibilityManager.current?.isReduceMotionEnabled` (API 33+) or `Settings.Global.ANIMATOR_DURATION_SCALE == 0f` and skip or shorten non-essential animations.
- Use `animateContentSize()` and `AnimatedVisibility` with a duration guard — `tween(if (reduceMotion) 0 else 300)`.

## Focus & Navigation

- Ensure logical focus order with `Modifier.focusProperties { next = ... ; previous = ... }` when the default traversal is wrong (e.g., floating overlays).
- Make non-default interactive elements `Modifier.focusable()` so physical-keyboard, D-pad, and switch-access users can reach them.

## Color & Contrast

- Text contrast must meet WCAG AA: **4.5:1** for body text, **3:1** for large text (≥18sp regular or ≥14sp bold).
- Never rely on color alone to convey state — pair color with an icon, text, or shape change.
- Provide a dark theme via `MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme())`.

## Localization

- All user-facing strings (including `contentDescription`, `stateDescription`, error messages, custom-action labels) must come from `strings.xml` via `stringResource(R.string.…)`.
- Never hardcode English — including in accessibility attributes.

## Patterns to Follow

```kotlin
// Compound row — merged for TalkBack
Row(
    modifier = Modifier
        .clickable(onClick = onClick)
        .semantics(mergeDescendants = true) { }
        .minimumInteractiveComponentSize()
) {
    Icon(
        imageVector = Icons.Default.Wifi,
        contentDescription = null // decorative, label comes from text
    )
    Column {
        Text(stringResource(R.string.network_title))
        Text(stringResource(R.string.network_subtitle))
    }
}

// Section heading
Text(
    text = stringResource(R.string.section_settings),
    style = MaterialTheme.typography.titleMedium,
    modifier = Modifier.semantics { heading() }
)

// Custom toggle with explicit role + state
Box(
    modifier = Modifier
        .toggleable(
            value = isOn,
            onValueChange = onToggle,
            role = Role.Switch
        )
        .semantics { stateDescription = if (isOn) on else off }
) { /* visual */ }

// Context-menu affordance with accessibility action mirror
val deleteLabel = stringResource(R.string.action_delete)
Row(
    modifier = Modifier.semantics {
        customActions = listOf(
            CustomAccessibilityAction(deleteLabel) { onDelete(); true }
        )
    }
) { /* swipeable content */ }

// Animation respecting reduce-motion
val reduceMotion = LocalAccessibilityManager.current?.isReduceMotionEnabled == true
AnimatedVisibility(
    visible = isExpanded,
    enter = fadeIn(tween(if (reduceMotion) 0 else 300)),
    exit = fadeOut(tween(if (reduceMotion) 0 else 300))
) { /* content */ }
```
