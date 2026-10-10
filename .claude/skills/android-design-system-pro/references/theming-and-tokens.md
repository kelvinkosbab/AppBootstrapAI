# Theme and tokens audit

## AppTheme structure

- **Exactly one theme composable** (`AppTheme`) wrapping `MaterialTheme` with app `colorScheme`, `typography`, `shapes`, and providing extended tokens. Flag: multiple themes per feature, `MaterialTheme(...)` called directly in screens, screens or previews rendered without the theme (they show the default purple baseline).
- **Applied once** at the root of each Activity's `setContent` and in every preview.
- **XML theme** (`themes.xml`) still matters for the window: parent `Theme.Material3.DayNight.NoActionBar` (or the splash theme with `postSplashScreenTheme`), with a `values-night` variant — otherwise the window background flashes the wrong color before Compose draws.

## Color

- **Schemes generated** (Material Theme Builder / `material-kolor` style tooling) from a brand seed — light, dark, and optionally medium/high-contrast variants. Hand-picked partial schemes leave roles at baseline defaults that clash.
- **Dynamic color** (`dynamicLightColorScheme` / `dynamicDarkColorScheme`, API 31+) behind an explicit decision, with a full brand fallback below API 31. Flag `dynamicColor = true` in an app whose screens still use literal brand colors — the mix looks broken on Android 12+.
- **Roles, not literals**: flag `Color(0x…)`, `Color.Red/Black/White`, `colorResource(R.color.*)` in feature composables.
- **On-pairs**: every surface/container background paired with its `on*` content role. `primaryContainer` background with `onSurface` text is a contrast bug in some schemes.
- **Surface hierarchy** via `surface`, `surfaceContainerLowest … surfaceContainerHighest` rather than custom grays or shadows.
- **Contrast**: 4.5:1 body / 3:1 large text and icons in light, dark, and (if dynamic) a couple of representative wallpapers.

## Extended tokens

- **Extended palette** (success/warning/info, chart series) as an `@Immutable` data class with light/dark instances, provided via `staticCompositionLocalOf` inside `AppTheme`, read through an `AppTheme.extendedColors` accessor.
- **Default value throws** (`error("AppTheme not applied")`) so a missing provider fails in previews/tests instead of rendering wrong colors.
- **`staticCompositionLocalOf` vs `compositionLocalOf`**: static for palette/spacing (rarely change, cheaper reads); non-static only for values that change within a subtree at runtime.
- **Don't** extend `ColorScheme` via extension properties that switch on `isSystemInDarkTheme()` — they ignore the theme actually applied (e.g., a forced-dark preview or an in-app theme setting).

## Typography

- `AppTypography` customizes the M3 scale once (brand `FontFamily`, weights, maybe line heights). Feature code uses `MaterialTheme.typography.<role>` and never sets `fontSize`, `fontFamily`, or `lineHeight` directly.
- **`sp` everywhere** for text; `dp` text sizes are a broken-tier finding (ignores font scale).
- **Font scale 200%**: Android 14+ nonlinear scaling. Check top screens with `@PreviewFontScale`; look for fixed-height containers (`Modifier.height(48.dp)` around text), `maxLines = 1` on primary content, and clipped buttons.
- Brand fonts via `res/font` or downloadable fonts with a declared fallback.

## Shape, spacing, elevation

- `AppShapes` (extra-small … extra-large) set once; feature code uses `MaterialTheme.shapes.*`. Flag literal `RoundedCornerShape(n.dp)` outside the design system.
- Spacing scale via `AppTheme.spacing`; batch off-scale `dp` literals per screen rather than reporting each.
- Tonal elevation over shadows; `Modifier.shadow` for hierarchy is usually a sign of pre-M3 styling.

## Material 3 Expressive

- `MaterialExpressiveTheme`, `MotionScheme`, and the expressive components require `@OptIn(ExperimentalMaterial3ExpressiveApi::class)`. Adoption belongs in `AppTheme` (one decision), not scattered per screen. Flag scattered opt-ins; note the API may change between Material 3 releases.
- Expressive motion must still respect *Remove animations* — see `android-accessibility-best-practices.md`.

## Edge-to-edge and system bars

- **Apps targeting SDK 35+ are edge-to-edge on Android 15+** whether or not they opt in. Check every Activity:
  - `enableEdgeToEdge()` called (consistent behavior on older versions too).
  - `Scaffold` `innerPadding` applied to content (a classic bug: `Scaffold { _ -> … }`).
  - Non-scaffold screens use `WindowInsets.safeDrawing` / `systemBars` / `ime` padding.
  - Lists use `contentPadding` with the navigation-bar inset so the last item scrolls clear.
  - Bottom-anchored buttons and FABs sit above the gesture/navigation bar.
- `window.statusBarColor` / `navigationBarColor` setters are deprecated and ignored under enforcement — flag them as dead code.
- Light/dark system-bar icons follow the theme (`enableEdgeToEdge` handles it with `SystemBarStyle.auto`).

## View interop

- Legacy XML screens read the same palette via a Material Components `Theme.Material3.*` with matching `colorPrimary`/`colorSurface` attributes, or are bridged through `ComposeView`. Two divergent palettes (XML vs Compose) is an inconsistency finding with a migration note (`xml-to-compose-migration-pro`).

## Audit sequence

1. Locate `AppTheme`; check schemes, dynamic-color decision, providers, XML window theme.
2. Count literal colors/sizes/shapes in feature modules.
3. Preview top screens: light/dark, dynamic on/off, 200% font scale, RTL.
4. Walk every Activity for edge-to-edge and insets.
