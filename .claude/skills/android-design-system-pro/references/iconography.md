# Iconography audit

Android icons live in four places — in-app UI, launcher, status bar, splash — each with its own spec. Audit each surface separately.

## Source and vocabulary

- **Icon source**: Material Symbols imported as vector drawables (one style — Outlined, Rounded, or Sharp — and one weight/fill/grade/optical-size setting app-wide) is the target. Flag:
  - `androidx.compose.material:material-icons-extended` in a module's dependencies — large artifact, slow compiles, R8-dependent; recommend importing only the glyphs in use as drawables. (Recent Material 3 releases also dropped the transitive `material-icons-core` dependency; confirm against the current release notes before assuming `Icons.Default.*` resolves.)
  - Mixed styles on one screen (Outlined toolbar + Filled list icons that aren't a selected state).
  - Raster PNG UI icons in `drawable-*dpi/` folders — convert to vectors.
- **Vocabulary**: an `AppIcons` object in `:core:designsystem` with meaning-named members (see `bootstrap.md`). Flag feature modules that reference `R.drawable.ic_*` or `Icons.*` directly — count them; they're the migration list.
- **Naming**: `ic_<meaning>` (UI), `ic_stat_<meaning>` (notification), `ic_launcher*` (launcher only).

## Size, tint, mirroring

- **Size**: `Icon` defaults to 24dp. Flag per-call-site `Modifier.size(20.dp)` / `size(28.dp)` drift on standard icons.
- **Touch target**: clickable icons must be `IconButton` (48dp) or carry `minimumInteractiveComponentSize()`. `Icon(…, Modifier.clickable { })` is a broken-tier finding — small target *and* no button role.
- **Tint**: flag `tint = Color(0x…)` / `Color.Black` / `colorResource(...)`. Expected: inherit `LocalContentColor` inside M3 containers, or a theme role (`colorScheme.error`). Multicolor artwork uses `Image`, not `Icon` (which tints).
- **RTL**: directional drawables (back, forward, send, chevrons, undo/redo) need `android:autoMirrored="true"`; non-directional ones must not have it. Verify with *Force RTL layout direction*.
- **State**: selected/unselected icon pairs (filled vs outlined) must be accompanied by selected semantics (`NavigationBarItem(selected = …)` does this; custom tabs need `Modifier.selectable` / `semantics { selected = … }`).

## Icon accessibility

| Situation | Expected |
|---|---|
| Icon next to text saying the same | `contentDescription = null` |
| `IconButton` / icon-only control | `contentDescription = stringResource(...)` describing the action |
| Standalone meaningful image | `contentDescription` from resources |
| Decorative illustration | `contentDescription = null` |
| Toggle icon (favorite) | `Modifier.toggleable` / `IconToggleButton` + `stateDescription` |

- `contentDescription = ""` → should be `null`.
- Hardcoded English descriptions → `stringResource`.
- Descriptions naming the glyph ("trash icon") → name the action ("Delete message").

## Launcher icon

Check `res/mipmap-anydpi-v26/ic_launcher.xml` (and `ic_launcher_round.xml`):

- **`<adaptive-icon>` present** with `<background>`, `<foreground>`, and **`<monochrome>`** (themed icons, Android 13+). Missing monochrome is a broken-tier finding for a polished app: under themed icons it shows full-color among tinted icons, or as a system-generated approximation.
- **Foreground fits the 66dp safe zone** of the 108dp canvas — open the foreground vector and check the artwork bounds; logos touching the 72dp visible edge get clipped by circular masks.
- **No baked shape/shadow** in the background or foreground layers.
- **`android:roundIcon`** points at the same adaptive icon; legacy `mipmap-*dpi/ic_launcher.png` only for API < 26 fallback.
- **Monochrome layer** is a silhouette of the foreground (single color, alpha defines shape), not a copy of the full-color layer.
- **Play listing icon** (512×512 PNG, 32-bit) matches the launcher artwork — out of repo, but note it.

## Notification icons

- **Small icon is alpha-only** (white on transparent). A colored or launcher icon passed to `setSmallIcon` renders as a solid white square — broken-tier.
- 24dp vector, `ic_stat_` prefix, no text, no fine detail.
- Accent via `setColor(...)` from the theme.
- FCM: `com.google.firebase.messaging.default_notification_icon` (and `…default_notification_color`) meta-data set, or data messages handled in-app.

## Splash screen

- **SplashScreen API** in use (`installSplashScreen()` before `super.onCreate()` in the launcher Activity; `Theme.SplashScreen` parent with `postSplashScreenTheme`). A custom splash Activity on Android 12+ shows *after* the system splash — two splashes is a finding.
- `windowSplashScreenAnimatedIcon` is a vector/AVD with the mark inside the circular safe area; `windowSplashScreenBackground` has a `values-night` variant.
- `setKeepOnScreenCondition` used only to wait for genuinely required startup state, never as a fixed delay.

## Audit sequence

1. Dependency check for `material-icons-extended`; count `Icons.*` and `R.drawable.ic_*` references outside the design-system module.
2. Sweep clickable icons and icon-only buttons for target size and descriptions.
3. Sweep tints for literals; preview top screens in dark theme and RTL.
4. Open the launcher, notification, and splash resources and check each spec above.
