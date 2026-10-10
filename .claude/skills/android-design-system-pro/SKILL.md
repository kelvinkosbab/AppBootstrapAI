---
name: android-design-system-pro
description: Bootstraps or audits an Android app's design system and iconography — Material Symbols drawables behind an AppIcons object, adaptive launcher icons with a monochrome layer, notification and splash icons, a Material 3 AppTheme with dynamic color and extended tokens, thin slot-based component wrappers, edge-to-edge, previews, and screenshot tests. Use when setting up the UI foundation of a new Compose app, when consolidating an existing app's hardcoded colors, sizes, and one-off components, or when reading, writing, or reviewing icon, theme, or shared-component code.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "Material 3 (m3.material.io) color/type/shape systems and Material Symbols, Compose Material 3 API and component API guidelines, Android adaptive/themed icon and notification icon specs, SplashScreen API, Android 15 edge-to-edge enforcement, Now in Android :core:designsystem"
---

Set up or review the UI foundation of an Android app: icons, theme, tokens, and core components. This is the deep companion to the always-on `android-iconography.md` and `android-design-system.md` rules — the rules steer while writing; this skill scaffolds a `:core:designsystem` module from scratch or audits a whole app against one.

Applies to Jetpack Compose apps (with View-interop notes). Pick the mode from the request:

- **Bootstrap** — a new app, or an app with no design-system module: generate the module skeleton using `references/bootstrap.md`, then fill the theme and components with the user's brand inputs (seed color, brand font, shape style, dynamic-color stance). Ask only for inputs you can't infer; default to a Material Theme Builder baseline with dynamic color on, and say so.
- **Audit** — an existing app: find and rank what breaks dark theme, dynamic color, font scaling, RTL, TalkBack, edge-to-edge, and visual consistency; propose an incremental migration.
- **Write/fix** — make the changes directly and summarize them in the same file-by-file format.

Review process (audit mode):

1. Inventory with the searches in `references/bootstrap.md` ("Audit searches") — literal colors, literal sizes, `material-icons-extended` usage, drawable references from feature modules, clickable boxes, missing insets handling. Count before reading files; the counts set priorities.
2. Audit icons using `references/iconography.md` — the icon source and `AppIcons` vocabulary, sizing/tint/mirroring, icon accessibility, launcher (adaptive + monochrome), notification and splash icons.
3. Audit theme and tokens using `references/theming-and-tokens.md` — `AppTheme` structure, color roles and pairs, dynamic color, extended tokens via CompositionLocal, type/shape/spacing scales, edge-to-edge.
4. Audit components using `references/components.md` — wrapper vs reimplementation, API shape (modifier, slots, Defaults objects), statelessness and stability, duplicates to converge, previews, the catalog, screenshot tests.

If doing a partial review, load only the relevant reference files.

## Core Instructions

- **Roles over values.** Feature code reads `MaterialTheme.colorScheme.*`, `MaterialTheme.typography.*`, `AppTheme.spacing.*`, `AppIcons.*`. A fix that replaces one literal with another literal is not a fix.
- **Material 3 first.** Wrap M3 components and use M3 roles; reimplementing a component or inventing a parallel color system is maintenance the team pays on every Material upgrade. Recommend custom only where M3 has no equivalent, and then as an extension of the theme.
- **Adaptation is the test.** For every token and component ask: does it survive dark theme, dynamic color, 200% font scale, RTL, edge-to-edge, and TalkBack? Report the setting that breaks it.
- **The design system is a module with a direction.** `:core:designsystem` depends on Compose/Material only; features depend on it. Flag inverted dependencies (components importing ViewModels, repositories, or `:data` models).
- **Incremental, never big-bang.** Migration plans move one screen or one token family at a time and keep the app shipping.
- **Severity by user impact**: broken (unreadable text in a theme, content under system bars, unlabeled icon-only control, white-square notification icon, clipped launcher icon, clickable box with no semantics) > inconsistent (duplicate components, off-scale spacing, mixed icon styles) > polish (expressive motion, tonal tuning).
- Cross-reference, don't duplicate: deep TalkBack/keyboard audits belong to `android-accessibility-pro`; recomposition and stability deep-dives to `android-compose-pro`; size-class layouts to `android-adaptive-layout-pro`; module wiring to `android-gradle-architecture-pro`.

## Output Format

**Bootstrap mode:** list the files created (module path → purpose), the brand inputs used (or the defaults chosen), and the next three adoption steps.

**Audit mode:** organize findings by file. For each issue: file/line, the violated principle, the setting or user affected (dark theme / dynamic color / font scale / RTL / TalkBack / edge-to-edge / consistency), and a brief before/after. Skip clean files. End with an inventory table and a prioritized migration plan.

Example finding:

### CartScreen.kt

**Line 58: clickable icon with a literal tint, no description, and a 24dp target — invisible on dark surfaces, announced as nothing, hard to hit.**

```kotlin
// Before
Icon(
    painter = painterResource(R.drawable.ic_delete),
    contentDescription = null,
    tint = Color(0xFF333333),
    modifier = Modifier.clickable { onRemove(item.id) },
)

// After
IconButton(onClick = { onRemove(item.id) }) {
    Icon(
        imageVector = AppIcons.Delete,
        contentDescription = stringResource(R.string.cart_remove_item, item.name),
    )
}
```

### Summary

| Inventory | Count |
|---|---|
| Literal colors (`Color(0x` / `Color.Red`) | 44 |
| Literal text sizes (`fontSize =`) | 19 |
| `Icons.*` from material-icons-extended | 31 |
| Distinct primary-button implementations | 3 |

1. **Broken:** `enableEdgeToEdge()` with no insets handling on `CheckoutScreen` — the pay button sits under the navigation bar on Android 15.
2. **Broken:** adaptive launcher icon has no `<monochrome>` layer; notification small icon is the full-color launcher icon.
3. **Inconsistent:** 3 primary-button implementations — converge on `AppPrimaryButton` in `:core:designsystem`.
4. **Polish:** move to `surfaceContainer*` roles instead of custom elevation shadows.

End of example.

## References

- `references/iconography.md` — Material Symbols drawables vs `material-icons-extended`, the `AppIcons` vocabulary, size/tint/mirroring, icon accessibility, adaptive + themed launcher icons, notification small icons, splash-screen icons.
- `references/theming-and-tokens.md` — `AppTheme` structure, color roles and on-pairs, dynamic color with brand fallback, extended palettes and spacing via CompositionLocal, type/shape scales, Material 3 Expressive, edge-to-edge and insets.
- `references/components.md` — wrapping M3 vs reimplementing, the core component set, API shape (modifier, slots, Defaults), stability, accessibility baked in, previews, the catalog, screenshot testing.
- `references/bootstrap.md` — the `:core:designsystem` module skeleton (files and starter code), Gradle wiring, audit searches, and the incremental migration playbook.
