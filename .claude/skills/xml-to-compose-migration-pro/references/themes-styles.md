# Themes & Styles: `styles.xml` → `MaterialTheme`

XML themes (`styles.xml`, `themes.xml`) translate to a `MaterialTheme` Composable that wraps the rest of the UI. The migration is mostly mechanical, with one important caveat: **`MaterialTheme` doesn't inherit from the XML theme.** If you mix `ComposeView` inside an XML layout, you have to explicitly set the theme inside each `setContent { }`.

## The mapping

| XML theme attribute | Compose equivalent |
|---------------------|--------------------|
| `<color name="primary">` in `colors.xml` | `colorScheme.primary` in `lightColorScheme()` / `darkColorScheme()` |
| `<style name="TextAppearance.MyApp.Body">` | `Typography.bodyLarge` / `bodyMedium` / etc. |
| `?attr/colorPrimary` reference | `MaterialTheme.colorScheme.primary` |
| `?attr/textAppearanceBodyLarge` | `MaterialTheme.typography.bodyLarge` |
| Shape attributes | `Shapes.small` / `medium` / `large` in the `MaterialTheme` |
| `android:windowBackground` | `Modifier.background(MaterialTheme.colorScheme.background)` on a `Surface` |

## A minimal `MaterialTheme` setup

```kotlin
// theme/Color.kt
val LightColors = lightColorScheme(
    primary = Color(0xFF0061A4),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFD0E4FF),
    onPrimaryContainer = Color(0xFF001D36),
    secondary = Color(0xFF535F70),
    onSecondary = Color(0xFFFFFFFF),
    surface = Color(0xFFFDFCFF),
    onSurface = Color(0xFF1A1C1E),
    background = Color(0xFFFDFCFF),
    onBackground = Color(0xFF1A1C1E),
    error = Color(0xFFBA1A1A),
    onError = Color(0xFFFFFFFF)
)

val DarkColors = darkColorScheme(
    primary = Color(0xFF9ECAFF),
    onPrimary = Color(0xFF003258),
    // ... full M3 color scheme
)

// theme/Type.kt
val AppTypography = Typography(
    bodyLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.5.sp
    ),
    // ... full M3 typography scale
)

// theme/Shape.kt
val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(4.dp),
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(12.dp),
    large = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(28.dp)
)

// theme/Theme.kt
@Composable
fun AppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context)
            else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColors
        else -> LightColors
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = AppTypography,
        shapes = AppShapes,
        content = content
    )
}
```

Then wrap the app:

```kotlin
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            AppTheme {
                AppNavHost()
            }
        }
    }
}
```

## Using the theme inside Composables

```kotlin
@Composable
fun SubmitButton(onClick: () -> Unit) {
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = MaterialTheme.colorScheme.onPrimary
        ),
        shape = MaterialTheme.shapes.medium
    ) {
        Text(
            text = stringResource(R.string.submit),
            style = MaterialTheme.typography.labelLarge
        )
    }
}
```

`MaterialTheme.colorScheme.X`, `MaterialTheme.typography.X`, `MaterialTheme.shapes.X` are the access points. Don't hardcode `Color(0xFF...)` literals in feature Composables — that's the same anti-pattern as hardcoded hex values in `colors.xml`.

## Dynamic color (Material You)

Android 12+ (API 31+) supports system-driven dynamic colors based on the user's wallpaper. Compose surfaces this via `dynamicLightColorScheme(context)` / `dynamicDarkColorScheme(context)`:

```kotlin
val colorScheme = when {
    dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
        if (darkTheme) dynamicDarkColorScheme(context)
        else dynamicLightColorScheme(context)
    }
    darkTheme -> DarkColors
    else -> LightColors
}
```

- **Opt-in via a `dynamicColor: Boolean` parameter** on your top-level `AppTheme` Composable. Default to `true` for users who want it; provide a setting to opt out.
- **Brand-strict apps should opt out** — dynamic color will override your primary brand color with the user's wallpaper-derived palette.
- **Older API levels fall through** to your static `LightColors` / `DarkColors`.

## Per-screen theme overrides

```kotlin
@Composable
fun DangerScreen() {
    val warningColors = MaterialTheme.colorScheme.copy(
        primary = Color.Red,
        onPrimary = Color.White
    )
    MaterialTheme(colorScheme = warningColors) {
        // Children see the overridden colors
        Button(onClick = {}) { Text("Delete") }
    }
}
```

Use sparingly — overriding the theme per-screen creates inconsistency. Usually better to use `MaterialTheme.colorScheme.error` semantics directly (`containerColor = MaterialTheme.colorScheme.errorContainer`) than to swap the whole scheme.

## When XML and Compose coexist

If a Fragment hosts a `ComposeView`, the Composable doesn't automatically inherit the XML theme. **Always wrap:**

```kotlin
composeView.setContent {
    AppTheme {   // ← required; otherwise default M3 colors apply
        MyCompositeWidget()
    }
}
```

For two-way: an `AndroidView { factory = ... }` inside a Composable creates a `View` that doesn't see `MaterialTheme`. If the View needs styled colors, pass them in as explicit `Color` parameters:

```kotlin
AndroidView(
    factory = { context ->
        MyView(context).apply {
            // Read MaterialTheme.colorScheme.primary from the outer Composable
            // and pass as an int:
            setPrimaryColor(primaryArgb)
        }
    }
)

// In the outer Composable:
val primaryArgb = MaterialTheme.colorScheme.primary.toArgb()
```

## Token-based theming for cross-cutting consistency

For apps where XML and Compose will coexist long-term, define design tokens in a shared source (an enum, sealed class, or generated TOML) and reference from both:

- XML reads from `colors.xml` / `dimens.xml` (which can be generated from the tokens).
- Compose reads from a `Tokens` object that mirrors the same values.

This is more work upfront but eliminates drift during migration. NiA and several open-source apps use this pattern.

## Migration steps

1. **Catalog every XML color** in `colors.xml` and `themes.xml`.
2. **Map each to a Material 3 role** — `primary` / `onPrimary` / `surface` / `onSurface` / `background` / etc. The M3 mapping is opinionated; don't force a 1:1.
3. **Define `LightColors` and `DarkColors`** as `lightColorScheme()` / `darkColorScheme()` calls.
4. **Catalog every `<style name="TextAppearance...">`** and map to a `Typography` slot.
5. **Build the `AppTheme` Composable** wrapping `MaterialTheme(...)`.
6. **Wrap the root `setContent { }`** in `AppTheme { ... }`.
7. **Replace every hardcoded color in Composables** with `MaterialTheme.colorScheme.X`.
8. **Keep XML themes** in place as long as XML screens exist — Compose theme is additive, not a replacement during the migration.

## Common pitfalls

- **Forgetting `AppTheme { }` around `setContent { }`** — Compose renders with default M3 colors, looks unstyled.
- **Hardcoded `Color(0xFFRRGGBB)` in feature Composables** — same anti-pattern as hardcoded hex in XML. Always go through `MaterialTheme.colorScheme.*`.
- **Mixing dynamic-color and brand-strict apps** without an opt-out — brand goes out the window on Android 12+.
- **`?attr/colorAccent` references left in XML** when the corresponding Compose theme uses M3 names — drift between XML and Compose worlds.
- **Long-lived `Color(...)` instances** — `Color` is an inline class; allocation is cheap, but if you find yourself memoizing colors, you're probably over-thinking it.
- **Custom `Shape` per-Composable** — usually the M3 `Shapes.small/medium/large` cover what you need. Per-Composable shapes are inconsistency in the making.
