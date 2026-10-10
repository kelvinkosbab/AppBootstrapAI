# Bootstrapping a :core:designsystem module

Use this for a new app, or an existing app with no shared UI module. The output is small on purpose: theme, tokens, the icon vocabulary, a few component wrappers, and previews. Everything else grows from real repetition.

## 1. Create the module

```kotlin
// settings.gradle.kts
include(":core:designsystem")
```

```kotlin
// core/designsystem/build.gradle.kts
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.example.core.designsystem"
    compileSdk = 36
    defaultConfig { minSdk = 26 }
    buildFeatures { compose = true }
}

kotlin { jvmToolchain(17) }

dependencies {
    api(platform(libs.androidx.compose.bom))
    api(libs.androidx.compose.material3)          // components in this module's public API
    api(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)
}
```

- `api` for Material 3 / Compose UI because the module's public composables expose their types (see `android-gradle-conventions.md` on `api` vs `implementation`).
- In a multi-module build with `build-logic/`, replace the plugin block with the project's library + Compose convention plugins (`android-gradle-architecture-pro`).
- Feature modules: `implementation(project(":core:designsystem"))`.

## 2. Files to generate

```
core/designsystem/src/main/
├── kotlin/com/example/core/designsystem/
│   ├── theme/
│   │   ├── Color.kt            # LightColors / DarkColors from Material Theme Builder
│   │   ├── ExtendedColors.kt   # success/warning/etc. + LocalExtendedColors
│   │   ├── Type.kt             # AppTypography (brand FontFamily)
│   │   ├── Shape.kt            # AppShapes
│   │   ├── Spacing.kt          # Spacing + LocalSpacing
│   │   └── Theme.kt            # AppTheme + AppTheme accessor object
│   ├── icon/
│   │   └── AppIcons.kt         # meaning-named ImageVectors backed by drawables
│   └── component/
│       ├── Buttons.kt          # AppPrimaryButton / AppSecondaryButton / AppTextButton
│       ├── TopAppBar.kt        # app defaults over TopAppBar
│       └── States.kt           # Loading / Empty / Error (with retry)
└── res/
    ├── drawable/               # ic_*.xml Material Symbols (one style)
    └── font/                   # brand fonts, if any
```

Skip anything the app doesn't need yet (no brand font → `Type.kt` only adjusts weights; no extended colors → no `ExtendedColors.kt`).

## 3. Starter code

```kotlin
// Spacing.kt
@Immutable
data class Spacing(
    val xs: Dp = 4.dp,
    val s: Dp = 8.dp,
    val m: Dp = 16.dp,
    val l: Dp = 24.dp,
    val xl: Dp = 32.dp,
)

val LocalSpacing = staticCompositionLocalOf { Spacing() }  // pure values; a default is safe here
```

```kotlin
// ExtendedColors.kt
@Immutable
data class ExtendedColors(
    val success: Color,
    val onSuccess: Color,
    val warning: Color,
    val onWarning: Color,
)

val LightExtendedColors = ExtendedColors(
    success = Color(0xFF1B6C3A), onSuccess = Color.White,
    warning = Color(0xFF7A5900), onWarning = Color.White,
)
val DarkExtendedColors = ExtendedColors(
    success = Color(0xFF8BD8A0), onSuccess = Color(0xFF00391A),
    warning = Color(0xFFF4BF48), onWarning = Color(0xFF402D00),
)

val LocalExtendedColors = staticCompositionLocalOf<ExtendedColors> {
    error("AppTheme not applied")
}
```

(Literal colors are correct *here* — this file is the token source. Run every role pair through a contrast check.)

```kotlin
// Theme.kt
@Composable
fun AppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit,
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColors
        else -> LightColors
    }
    CompositionLocalProvider(
        LocalExtendedColors provides if (darkTheme) DarkExtendedColors else LightExtendedColors,
        LocalSpacing provides Spacing(),
    ) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = AppTypography,
            shapes = AppShapes,
            content = content,
        )
    }
}

object AppTheme {
    val extendedColors: ExtendedColors
        @Composable @ReadOnlyComposable get() = LocalExtendedColors.current
    val spacing: Spacing
        @Composable @ReadOnlyComposable get() = LocalSpacing.current
}
```

```kotlin
// AppIcons.kt
object AppIcons {
    val Back: ImageVector
        @Composable get() = ImageVector.vectorResource(R.drawable.ic_arrow_back)   // autoMirrored
    val Settings: ImageVector
        @Composable get() = ImageVector.vectorResource(R.drawable.ic_settings)
    val Delete: ImageVector
        @Composable get() = ImageVector.vectorResource(R.drawable.ic_delete)
    val Favorite: ImageVector
        @Composable get() = ImageVector.vectorResource(R.drawable.ic_favorite)
    val FavoriteFilled: ImageVector
        @Composable get() = ImageVector.vectorResource(R.drawable.ic_favorite_fill)
}
```

```kotlin
// States.kt
@Composable
fun AppErrorState(
    message: String,
    onRetry: () -> Unit,
    retryLabel: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth().padding(AppTheme.spacing.l),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AppTheme.spacing.m),
    ) {
        Text(message, style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center)
        AppPrimaryButton(onClick = onRetry) { Text(retryLabel) }
    }
}

@PreviewLightDark
@PreviewFontScale
@Composable
private fun AppErrorStatePreview() {
    AppTheme(dynamicColor = false) {
        Surface { AppErrorState(message = "Couldn't load your feed.", onRetry = {}, retryLabel = "Retry") }
    }
}
```

(Preview strings are literal on purpose — previews aren't shipped UI. Shipped callers pass `stringResource(...)`.) `AppPrimaryButton` is the wrapper shown in `android-design-system.md`.

## 4. Icons

- **UI glyphs**: Android Studio ▸ New ▸ Vector Asset ▸ Clip Art (Material Symbols, set the style once), or download the Android XML from fonts.google.com/icons. Add `android:autoMirrored="true"` to directional glyphs. Register each in `AppIcons`.
- **Launcher**: New ▸ Image Asset ▸ Launcher Icons (Adaptive and Legacy) from vector foreground art; add a `<monochrome>` silhouette drawable to `mipmap-anydpi-v26/ic_launcher.xml` (the wizard can generate one from the foreground if it's a clean silhouette — otherwise draw it). Launcher resources live in `:app`, not the design-system module.
- **Notification**: New ▸ Image Asset ▸ Notification Icons → `ic_stat_*` (alpha-only).
- **Splash**: `Theme.SplashScreen` in `:app` with `windowSplashScreenAnimatedIcon` pointing at a vector inside the safe circle.

## 5. Audit searches (existing apps)

Run from the repo root; counts drive priority. Exclude the design-system module where noted.

```bash
# Literal colors in feature code
rg -n --type kotlin 'Color\(0x|Color\.(Red|Blue|Green|Black|White|Gray)\b|colorResource\(' --glob '!**/designsystem/**' | wc -l
# Literal text styling
rg -n --type kotlin 'fontSize\s*=|fontFamily\s*=|lineHeight\s*=' --glob '!**/designsystem/**' | wc -l
# Literal shapes
rg -n --type kotlin 'RoundedCornerShape\(' --glob '!**/designsystem/**' | wc -l
# Icon sources
rg -n 'material-icons-extended|material.icons.extended' --glob '*.kts' --glob '*.toml'
rg -n --type kotlin 'Icons\.(Default|Filled|Outlined|Rounded|Sharp|AutoMirrored)\.' --glob '!**/designsystem/**' | wc -l
rg -n --type kotlin 'R\.drawable\.ic_' --glob '!**/designsystem/**' | wc -l
# Clickable non-controls (likely reimplemented buttons / undersized icon taps)
rg -n --type kotlin -U '(Box|Row|Column|Text|Icon)\([^)]*\n?[^)]*Modifier[^)]*\.clickable' | wc -l
# Edge-to-edge / insets
rg -n --type kotlin 'enableEdgeToEdge\(' 
rg -n --type kotlin 'statusBarColor|navigationBarColor'
rg -n --type kotlin 'Scaffold\([^)]*\)\s*\{\s*_\s*->' 
# Launcher / notification icons
ls app/src/main/res/mipmap-anydpi-v26/ 2>/dev/null && rg -n '<monochrome' app/src/main/res/mipmap-anydpi-v26/
rg -n --type kotlin 'setSmallIcon\(' 
```

## 6. Migration playbook

1. **Create `:core:designsystem` with `AppTheme` reproducing today's colors** (`dynamicColor = false`) so nothing visibly changes. Ship that.
2. **Fix broken-tier issues first**: content under system bars, unreadable on-pairs in dark theme, unlabeled icon buttons, clickable-box "buttons," white-square notification icon, missing monochrome layer.
3. **Migrate screen by screen** as features are touched: literals → roles/tokens, `Icons.*` / `R.drawable` → `AppIcons`, local buttons → wrappers. One screen or one token family per PR.
4. **Drop `material-icons-extended`** once no module references `Icons.*` from it.
5. **Converge duplicates** per role.
6. **Turn on dynamic color last** (if the product wants it), once no screen relies on literal brand colors.
