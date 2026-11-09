---
description: Localization conventions for Android — strings.xml discipline, stringResource / pluralStringResource, plurals, positional format args, locale-aware formatters, RTL with start/end, translator context.
globs: "**/*.{kt,kts,xml}"
paths:
  - "**/*.{kt,kts,xml}"
must:
  - "Every user-facing string lives in `res/values/strings.xml`, read with `stringResource` or `getString`."
  - "Use positional format arguments (`%1$s`, `%2$d`), never bare `%s` or `%d`."
  - "Use `<plurals>` for any count-dependent string; never build plurals in code."
  - "Use `start`/`end`, never `left`/`right`; format numbers and dates with locale-aware formatters."
---

# Android Localization Best Practices

The must-follow rules for user-facing strings on Android. Compose and XML examples, plural and format-argument details, and the translation pipeline are in [`localization-pro/references/android.md`](../skills/localization-pro/references/android.md); read the matching section only when a line below isn't enough. Audit with `localization-pro`.

## Source of truth

- **Every user-facing string is in `res/values/strings.xml`**, with overrides in `values-<lang>/` and `values-<lang>-r<REGION>/`. IDs are `snake_case`, namespaced by feature (`settings_save_button`).
- **`stringResource(R.string.…)` in Compose, `context.getString(…)` elsewhere.** No literal strings in composables, `contentDescription`, or `setText`.
- Read strings per render, not into constants at startup, so a language change takes effect.

## Format arguments and plurals

- **Positional arguments only** (`%1$s`, `%2$d`), with the right type token. Pass them to `stringResource`; never build sentences with Kotlin templates.
- **`<plurals>` for every count-dependent string** (`pluralStringResource` / `getQuantityString`), passing the count twice when it's also shown. Never `if (count == 1)`.

## Formatting

- **Locale-aware formatters**: `NumberFormat.getCurrencyInstance(locale)`, `java.time` `DateTimeFormatter`. No `String.format` for user-visible numbers, no per-render `SimpleDateFormat`.
- Code that formats outside Compose takes a `Locale` parameter so tests can pin it.

## Right-to-left

- **`android:supportsRtl="true"`** in the manifest.
- **`start` / `end`**, never `left` / `right` (Compose modifiers, `paddingStart`, gravity).
- Mirror directional vectors with `android:autoMirrored="true"`; don't mirror logos or photos. Test with "Force RTL layout direction".

## Translator context and pipeline

- **A comment on every string or group**, explaining where it appears and what each argument is.
- `lintDebug` flags missing translations in CI. Translated `values-<locale>/` files come from the translation tool, not hand edits in PRs.
