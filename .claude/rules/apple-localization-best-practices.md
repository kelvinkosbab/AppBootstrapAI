---
description: Localization conventions for Apple platforms — String Catalogs, type-safe Strings facade, String(localized:), plurals, format args, locale-aware formatters, RTL, translator context.
globs: "**/*.swift"
paths:
  - "**/*.swift"
must:
  - "New strings go in String Catalogs and are read through the typed `Strings` facade; UI never calls `String(localized:)` directly."
  - "Use catalog plural variations, never `count == 1 ? … : …`."
  - "Format numbers, dates, and currency with locale-aware formatters, never `String(format:)`."
  - "Use `.leading`/`.trailing`, never `.left`/`.right`; give every entry a translator comment."
---

# Apple Localization Best Practices

The must-follow rules for user-facing strings on Apple platforms. The facade code, plural catalog entries, formatter examples, and Xcode 27 catalog tooling are in [`localization-pro/references/apple.md`](../skills/localization-pro/references/apple.md); read the matching section only when a line below isn't enough. Audit with `localization-pro`.

## Source of truth

- **String Catalogs (`.xcstrings`)**, one per module. Don't add new entries to legacy `.strings` / `.stringsdict`; migrate per module.
- **A typed `Strings` facade** (`Strings.<Section>.<key>`) returning `LocalizedStringResource` is the only place that calls `String(localized:)` or `NSLocalizedString`. Parameterized strings are facade functions.
- **No hardcoded literals in UI**: `Text("Save")`, `Button("Cancel")`, alert titles, and accessibility labels all come from the facade.

## Plurals and sentences

- **Plural variations in the catalog** for every count, even when English looks obvious. Never `count == 1 ? … : …`.
- **Never concatenate sentence fragments.** Translators need to reorder; use one parameterized resource.

## Formatting

- **`.formatted()`, `FormatStyle`, and `Text(_:format:)`** for numbers, dates, currency, and measurements. No `String(format:)` for user-visible values.
- No `DateFormatter()` per render; cache a `static let` or use `FormatStyle`. Code that formats outside a view takes a `Locale` parameter so tests can pin it.

## Right-to-left

- **`.leading` / `.trailing`**, never `.left` / `.right`.
- Mirror directional images with `.flipsForRightToLeftLayoutDirection(true)`; don't mirror logos or photos.
- Check screens with the Right-to-Left, Double-Length, and Accented pseudolanguages.

## Translator context

- **Every entry has a `comment:`** saying where it appears and what each argument is. Keys carry context too (`settings.save_button`).
- Mark brand names and code tokens **do not translate** in the comment.
- Machine or agent translations (Xcode 27 "Generate Translations") are drafts for human review, never new keys.
