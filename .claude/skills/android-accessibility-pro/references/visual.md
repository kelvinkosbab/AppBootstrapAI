# Visual accessibility — contrast, text scaling, targets, color, motion

Low-vision users vastly outnumber TalkBack users. This audit covers what the sighted-but-low-vision user gets.

## Contrast

- **WCAG AA ratios**: 4.5:1 body text, 3:1 large text (≥ 18sp regular / ≥ 14sp bold) and essential non-text UI (focus indicators, control outlines, meaningful icons).
- **Audit both themes.** Failures cluster in the theme the team doesn't develop in — dark theme's low-alpha `onSurfaceVariant` text on elevated surfaces is the classic. The **Accessibility Scanner** app and Compose preview tooling both compute ratios; name one in each contrast finding.
- **Material color roles pass by construction** when used as designed (`onPrimary` on `primary`, `onSurface` on `surface`); findings come from mixed roles (`onSurfaceVariant` on `surfaceVariant` at reduced alpha), hardcoded hex, and brand colors on tinted buttons — verify those numerically.
- **Text over images/gradients** needs a scrim or minimum-luminance guarantee — a ratio that holds on one photo fails on the next.
- Don't invent a high-contrast theme toggle — support the system dark theme properly and keep ratios AA in both.

## Dynamic text scaling

- **`sp` for all text sizes, never `dp`** — `dp` text ignores the user's font-size setting. Also audit for `fontSize = 14.sp` on hardcoded small text that turns unreadable at 200% (Android 14+ supports non-linear scaling up to 200%).
- **Test at maximum font size** (Settings ▸ Display ▸ Font size ▸ largest): required controls must remain visible and reachable; truncation of critical content is task-blocking.
- **`maxLines = 1` + ellipsis on critical content** without a full-text fallback (semantics text, expandable row) is a finding.
- **Fixed heights kill scaling**: hardcoded `Modifier.height()` on text containers clips at large scales — prefer `heightIn(min = ...)`.
- Icons beside scaling text: consider `Modifier.size(with density-aware scaling)` or at minimum verify layout survives the icon *not* scaling.

## Touch targets

- **≥ 48dp × 48dp** for every interactive element — `Modifier.minimumInteractiveComponentSize()` restores shrunken `IconButton`s/checkboxes. Visual size may be smaller; the *target* may not.
- Adjacent small targets (icon strips, chip rows) need spacing so targets don't overlap.

## Color-independence

- **State never rides on color alone**: error/success/selected need an icon, text, or shape change alongside color. Red-vs-green status dots are the canonical finding.
- Charts and category coding: pair color with patterns, shapes, or direct labels.
- Link/action affordances inside text need more than a color shift (underline, weight).

## Motion

- **Respect "Remove animations"**: gate non-essential animation on the system setting — `Settings.Global.ANIMATOR_DURATION_SCALE == 0f` / `ValueAnimator.areAnimatorsEnabled()`, wrapped once in a `rememberReduceMotion()`-style composable, then `tween(if (reduceMotion) 0 else 300)`.
- **What must reduce**: auto-playing carousels, parallax, shimmer placeholders, looping decorations. Subtle fades may stay.
- Auto-playing video/animated images need a pause affordance regardless of the motion setting.

## Audit sequence

1. Per screen, per theme: compute ratios for body text, secondary text, essential icons; list AA misses with the numbers.
2. Grep for `dp`-typed text sizes, `maxLines = 1` on critical content, fixed text-container heights.
3. List interactive elements under 48dp (`IconButton` with custom `size`, custom clickable icons).
4. List every color-conveyed state; check each for a non-color channel.
5. Grep animation sites for missing reduce-motion gates.
