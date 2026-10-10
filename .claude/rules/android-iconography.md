---
description: Android iconography — Material Symbols as vector drawables behind a typed AppIcons object, icon sizing and tinting via LocalContentColor, RTL auto-mirroring, icon accessibility, adaptive launcher icons with a monochrome layer for themed icons, notification icons, and the splash-screen icon
globs: "**/*.{kt,kts,xml}"
---

# Android Iconography

Icons on Android show up in four places with four different rules: in-app UI (Compose `Icon`), the **launcher** (adaptive icons, themed icons), the **status bar** (notification icons), and the **splash screen**. Most shipped icon bugs are the same few — a 2 MB icon library pulled in for ten glyphs, hardcoded tints that vanish in dark theme, icon-only buttons TalkBack can't name, launcher icons with no monochrome layer, and full-color notification icons that render as a white square. This rule pins the conventions; for a full audit or to scaffold an icon system, invoke the **`android-design-system-pro`** skill.

## Source: Material Symbols as Vector Drawables

- **Use Material Symbols** (Outlined / Rounded / Sharp; one style app-wide) for UI glyphs. Import only the glyphs you use as **vector drawables** — via Android Studio's *Vector Asset* tool or the XML download on fonts.google.com/icons — into the design-system module's `res/drawable/`.
- **Avoid `material-icons-extended` in new code.** It's a very large artifact (thousands of `ImageVector`s, slow to compile, reliant on R8 to strip) and Google's guidance has moved to Material Symbols drawables; recent Material 3 releases also stopped pulling `material-icons-core` in transitively, so code relying on `Icons.Default.*` may need the dependency added explicitly. Verify against the current Compose Material 3 release notes when upgrading; migrate existing `Icons.*` usages as you touch them.
- **Pick one style and weight** (e.g., Rounded, weight 400, fill 0, optical size 24) and import every glyph with the same settings — mixing styles reads as broken.
- **Custom/brand glyphs** are also vector drawables on a 24dp grid with the same stroke weight. Never ship raster PNG icons for UI glyphs; never use bitmap density buckets for something a vector can draw.

## A Typed Icon Object — One Vocabulary

Call sites shouldn't know which drawable backs "delete." Centralize, the way Now in Android's `NiaIcons` does:

```kotlin
/** The app's icon vocabulary. Name by meaning, not by glyph. */
object AppIcons {
    val Settings: ImageVector
        @Composable get() = ImageVector.vectorResource(R.drawable.ic_settings)
    val Delete: ImageVector
        @Composable get() = ImageVector.vectorResource(R.drawable.ic_delete)
    val Back: ImageVector
        @Composable get() = ImageVector.vectorResource(R.drawable.ic_arrow_back) // autoMirrored in XML
}

// Call site
Icon(imageVector = AppIcons.Delete, contentDescription = stringResource(R.string.action_delete))
```

- **Name by meaning** (`Delete`, `Favorite`) so swapping the glyph is a one-line change.
- **Drawable names**: `ic_<meaning>` for UI glyphs, `ic_stat_<meaning>` for notification icons, `ic_launcher*` reserved for the launcher.
- `AppIcons` lives in `:core:designsystem` (see [`android-design-system.md`](./android-design-system.md)); feature modules never reference `R.drawable.ic_*` directly.

## Size, Tint, Mirroring

- **24dp is the standard icon size** (`Icon` defaults to it). Change size with `Modifier.size(...)` only for deliberate emphasis (empty-state illustrations), not per screen.
- **Touch targets are 48dp** — `IconButton` provides it; a bare `Icon` with `Modifier.clickable` does not. Use `IconButton`, or add `Modifier.minimumInteractiveComponentSize()`.
- **Let `LocalContentColor` tint the icon.** `Icon` inside a `Button`, `TopAppBar`, or `NavigationBarItem` picks up the right on-color automatically; pass `tint` only from the theme (`MaterialTheme.colorScheme.error`), never `Color(0xFF…)`. Use `Image` (not `Icon`) for multicolor artwork you don't want tinted.
- **Directional glyphs mirror in RTL**: `android:autoMirrored="true"` on the vector (back/forward arrows, chevrons, send). Don't mirror non-directional glyphs (checkmarks, clocks, logos). See [`android-localization-best-practices.md`](./android-localization-best-practices.md).
- **Selected/unselected pairs** (filled vs outlined tab icons) come from the same style; state must also be conveyed by the item's selected semantics, not the glyph alone.

## Icon Accessibility

- **Meaningful icons** set `contentDescription` from `stringResource(...)`. **Decorative icons** (next to text that says the same thing) pass `contentDescription = null` — not `""`.
- **Icon-only buttons always have a description** — an `IconButton` whose `Icon` has `contentDescription = null` is announced as just "button."
- **Describe the action, not the glyph**: "Delete message," not "trash can."
- Keep descriptions short and emoji-free (they're also the braille output). See [`android-accessibility-best-practices.md`](./android-accessibility-best-practices.md).

## Launcher Icon — Adaptive, With a Monochrome Layer

```xml
<!-- res/mipmap-anydpi-v26/ic_launcher.xml -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
```

- **Generate with Android Studio's Image Asset Studio** (Launcher Icons → Adaptive and Legacy) from vector sources, so every density and the legacy fallback come out consistent.
- **Layers are 108×108dp; only the inner ~72dp is visible** and the mask varies by launcher (circle, squircle, teardrop). Keep the logo inside the **66dp safe zone** — anything outside can be clipped.
- **Background is a full-bleed color or simple pattern**; don't bake a shape, shadow, or rounded corners — the launcher masks and animates the layers.
- **Always provide the `<monochrome>` layer** (Android 13+ themed icons): a single-color silhouette of the foreground. Without it, users with themed icons see your full-color icon among tinted ones — or a system-generated approximation on newer releases, which rarely looks as good as a designed one.
- **Round icon** (`android:roundIcon`) should point at the same adaptive icon — legacy round PNGs are only for API < 26.
- **The Play Store listing icon is separate** — a 512×512 32-bit PNG uploaded in Play Console. Keep it visually identical to the launcher icon.

## Notification Icons

- **The small icon is a silhouette: white on transparent, alpha only.** The system ignores its colors — a full-color icon renders as a solid white square. 24dp, simple shapes, no text.
- Set it explicitly (`setSmallIcon(R.drawable.ic_stat_message)`); use `setColor(...)` from the theme for the accent. Never reuse the launcher icon here.
- For FCM, also set `com.google.firebase.messaging.default_notification_icon` in the manifest so system-delivered notifications don't fall back to the launcher icon.

## Splash Screen Icon

- **Use the SplashScreen API** (`androidx.core:core-splashscreen`, `installSplashScreen()` before `super.onCreate`) — Android 12+ shows a system splash regardless, so a custom splash Activity just adds a second one.
- **`windowSplashScreenAnimatedIcon`** is a vector (or animated vector) sized like an adaptive-icon foreground — keep the mark inside the centered circular safe area, or it gets clipped. `windowSplashScreenBackground` comes from the theme, with a night variant.

## Common Pitfalls

- **`material-icons-extended` for a handful of glyphs** — build-time and APK cost; import the drawables you use.
- **`R.drawable.ic_*` referenced from feature modules** — bypasses the `AppIcons` vocabulary.
- **Hardcoded `tint = Color(0xFF…)`** — invisible in dark theme or on colored surfaces. Let `LocalContentColor` or a theme role decide.
- **Clickable bare `Icon` under 48dp.** Use `IconButton`.
- **`contentDescription = ""`** for decorative icons — use `null`.
- **Unmirrored back arrows in RTL.** `android:autoMirrored="true"`.
- **Adaptive icon with no monochrome layer** — sticks out under themed icons.
- **Logo outside the 66dp safe zone** — clipped on some launchers.
- **Full-color notification small icon** — a white square in the status bar.
- **A custom splash Activity on Android 12+** — users see two splashes.
