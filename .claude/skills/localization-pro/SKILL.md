---
name: localization-pro
description: Audits and fixes localization in SwiftUI and Jetpack Compose apps — String Catalogs and a typed Strings facade, strings.xml and positional arguments, plurals, locale-aware formatting, right-to-left layout, translator comments, and pseudo-localization. Use when adding a language, before a localized release, when strings are hardcoded or concatenated, or when RTL or plural output looks wrong.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
---

Make every user-facing string translatable, correctly pluralized, formatted for the reader's locale, and laid out for right-to-left languages. This is the deep companion to the always-on `apple-localization-best-practices.md` and `android-localization-best-practices.md` rules. Report only genuine problems.

Load only the reference for the platform in scope:

- `references/apple.md` — String Catalogs, the typed `Strings` facade with `LocalizedStringResource`, SwiftUI usage, plural variations, `FormatStyle`, RTL, translator comments, Xcode 27 catalog tooling, and pseudolanguages.
- `references/android.md` — `strings.xml` layout and naming, `stringResource` / `pluralStringResource`, positional format arguments, `<plurals>`, `java.time` and `NumberFormat`, RTL with `start` / `end`, translator comments, other resource types, and the translation pipeline.

## Audit Process

1. **Hardcoded strings.** Search UI code for literal strings in `Text(`, `Button(`, alerts, `contentDescription`, and accessibility labels. Each must come from the facade or a string resource.
2. **Sentence building.** Flag string concatenation and Kotlin or Swift interpolation that builds a sentence outside a localized resource.
3. **Plurals.** Flag `count == 1` ternaries and `if` branches choosing between singular and plural words.
4. **Format arguments.** Android: bare `%s` / `%d` in strings with two or more arguments. Apple: `String(format:)` for user-visible values.
5. **Formatting.** Number, date, and currency output goes through locale-aware formatters; no per-render formatter allocation.
6. **Right-to-left.** `.left` / `.right` or `left` / `right` in layout code; directional images that don't mirror; Android `supportsRtl` missing.
7. **Translator context.** Entries without comments, ambiguous keys, and brand names not marked do-not-translate.
8. **Verify** with the pseudolanguages (Double-Length, Accented, Right-to-Left) or Force RTL on the screens you changed.

## Output Format

Group findings by severity: **blocking** (hardcoded or concatenated user-facing text, wrong plurals, crashes from mismatched format types), **degraded** (locale-unaware formatting, RTL breakage, missing translator comments), **polish** (key naming, formatter caching). Give each as file:line, what a reader in another language sees, and the fix with before/after. End with the count per severity and the first three fixes.
