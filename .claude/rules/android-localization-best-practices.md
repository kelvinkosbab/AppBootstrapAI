---
description: Localization conventions for Android — strings.xml discipline, stringResource / pluralStringResource, plurals, positional format args, locale-aware formatters, RTL with start/end, translator context.
globs: "**/*.{kt,kts,xml}"
---

# Android Localization Best Practices

Every user-facing string is localized. *Including* `contentDescription`, `stateDescription`, error messages, dialog titles, and short pieces of text that "are obviously the same in every language" (they aren't). The cost of localizing from day one is near zero; retrofitting after launch is expensive.

## Source of Truth: `strings.xml`

- **Every user-facing string lives in `res/values/strings.xml`** as the base (English) source.
- **Locale-specific overrides go in `res/values-<locale>/strings.xml`** (e.g., `values-de/`, `values-es/`, `values-ja/`).
- **Region-specific overrides** use `values-<lang>-r<REGION>/strings.xml` (`values-en-rGB/`, `values-pt-rBR/`).
- **Don't read strings from drawables, raw resources, or hardcoded constants** — they bypass translation pipelines.
- **String IDs are `snake_case`** by convention, namespaced by feature: `settings_save_button`, `errors_network_unavailable`, `notifications_user_sent_message`.

## Compose Usage

```kotlin
Text(text = stringResource(R.string.settings_save_button))

// Format args — let the resource framework handle positional substitution
Text(text = stringResource(R.string.greeting_user, user.displayName))

// Plurals — quantity-aware
Text(text = pluralStringResource(R.plurals.items_count, count, count))
```

- **Always `stringResource(R.string.…)`**, never literal string parameters in Composables.
- **`pluralStringResource(id, quantity, *formatArgs)`** for any count-dependent text.
- **Format args go *outside* the string template** — pass them as varargs to `stringResource` / `pluralStringResource`. Never pre-format with Kotlin string templates (`"$count items"`) in a Composable.

## Format Arguments — Always Positional

```xml
<!-- Good -->
<string name="user_sent_message">%1$s sent you a message.</string>
<string name="copied_n_of_m">Copied %1$d of %2$d files.</string>

<!-- Bad — non-positional %s/%d break when translators reorder args -->
<string name="user_sent_message">%s sent you a message.</string>
```

- **Use positional args (`%1$s`, `%2$d`, `%3$f`)**, never the bare `%s` / `%d` shorthand. Translators frequently need to reorder arguments (subject-verb-object differences across languages); positional args make that legal, bare ones don't.
- **Type tokens matter:** `%1$s` (string), `%1$d` (decimal int), `%1$f` (float), `%1$tF` (date). Mismatched types crash at format time.
- **Lint will warn** on missing positional indexes when there are 2+ args — don't suppress.

## Plurals

```xml
<plurals name="items_count">
    <item quantity="zero">No items</item>
    <item quantity="one">%d item</item>
    <item quantity="few">%d items</item>
    <item quantity="many">%d items</item>
    <item quantity="other">%d items</item>
</plurals>
```

- **Use `<plurals>` for any count-dependent string**, even if English only has `one` / `other`. Russian has 4 forms, Polish 3, Arabic 6.
- **`pluralStringResource` in Compose**, `getQuantityString(R.plurals.id, count, count)` in non-Compose code.
- **Pass the count *twice* if you want it formatted into the result** — once for plural selection, again as a format arg. The runtime doesn't auto-substitute it.
- **Never** stitch plurals together in code (`"$count " + (if (count == 1) "item" else "items")`).
- **`zero`, `two`, `few`, `many` quantities** are language-dependent. Define the ones English needs (`one`, `other`); the system falls back to `other` for any locale-quantity combo you didn't specify, but you can override per-locale `strings.xml`.

## Locale-Aware Formatting

Numbers, dates, currencies, and units must format per-locale. Never use `"$amount"` Kotlin templates or `String.format("%.2f", value)` for user-visible output.

```kotlin
// Numbers — respects locale separators (1,234.56 vs 1.234,56)
val formatted = NumberFormat.getNumberInstance().format(itemCount)

// Currency — uses the user's locale
val price = NumberFormat.getCurrencyInstance().apply {
    currency = Currency.getInstance("USD")
}.format(amount)

// Dates — modern java.time API
val date = LocalDateTime.now().format(
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM)
)

// Or with an explicit locale (recommended for testability)
val date = formatter.withLocale(Locale.US).format(timestamp)
```

- **Prefer `java.time` (`DateTimeFormatter`, `LocalDateTime`) over `SimpleDateFormat`.** SimpleDateFormat is not thread-safe and harder to test.
- **`NumberFormat.getCurrencyInstance(locale)` and friends accept a `Locale`** — pass it explicitly in code that produces user-visible strings outside Compose, so tests can inject `Locale.US` or `Locale.GERMANY` deterministically.
- **In Compose, read the current locale** via `LocalConfiguration.current.locales[0]` if you need it for a `Formatter` instance; cache via `remember`.

## Right-to-Left (RTL) Support

- **`<application android:supportsRtl="true">`** in `AndroidManifest.xml` — required for any RTL layout to mirror.
- **Use `start` / `end` modifiers, never `left` / `right`:**
  - `Modifier.padding(start = 16.dp, end = 16.dp)` ✓
  - `Modifier.padding(left = 16.dp, right = 16.dp)` ✗
- **Compose `Modifier.padding(horizontal = X)`** is RTL-safe (applies to start+end uniformly).
- **For `View`-based layouts**, use `paddingStart`/`paddingEnd`, `marginStart`/`marginEnd`, gravity `start|end`.
- **Mirror directional drawables via `android:autoMirrored="true"`** on the `<vector>` or programmatically. Mirror back arrows, progress indicators, breadcrumbs. Do **not** mirror logos, photographs, icons that have no left/right meaning.
- **Test RTL via Settings → Developer options → "Force RTL layout direction"**, or run on an Arabic / Hebrew locale. Catches hardcoded `left`/`right`.

## Translator Context

A translator opening your `strings.xml` sees only the ID and the source value. Without context, *"Save"* is ambiguous (verb? noun? what's being saved?).

```xml
<!-- Comment block, applies to all subsequent entries until the next comment -->

<!--
  Settings screen.
  These strings appear on the user's account preferences page.
-->
<string name="settings_save_button">Save</string>
<string name="settings_save_in_progress">Saving…</string>

<!--
  Error messages shown in toast banners.
  %1$s is the human-readable cause string returned by the network layer.
-->
<string name="errors_network_unavailable">Couldn't reach the server: %1$s</string>
```

- **Group strings by feature** with comment blocks describing where they appear.
- **Document format-arg meaning** in the comment (`%1$s is the user's display name`).
- **Use descriptive IDs.** `settings_save_button` reads like a sentence; `btn_1` does not.

## Resources Beyond `strings.xml`

- **`<plurals>`** in `strings.xml` (or a separate `plurals.xml`) for count-dependent strings.
- **`<string-array>`** for fixed lists (locale categories, predefined options).
- **`values-<locale>/dimens.xml`** for locale-specific layout adjustments (e.g., extra width for German).
- **`drawable-<locale>/`** for locale-specific imagery (rare, but possible).

## Translation Pipeline

- **`./gradlew lintDebug`** flags missing translations. Add to CI as a non-blocking warning at minimum; blocking once translation is part of the release flow.
- **Use Lokalise / Crowdin / Translation Memory tools** for multi-language projects. Export `strings.xml`, translate, import.
- **Don't manually edit `values-<locale>/strings.xml` files in PRs** for translation updates — that's what the translation tooling is for. PRs touching translated files should be machine-generated or come from translators.

## Common Pitfalls

- **Hardcoded literals.** `Text("Save")`, `Button(onClick = {}) { Text("Cancel") }`, `setContentDescription("Submit")`. All need `stringResource`.
- **Kotlin string templates for sentences.** `"$user sent you a message"` — translators can't reorder. Use a parameterized resource and pass `user` as a `%1$s` arg.
- **Singular/plural via `if`.** `if (count == 1) "item" else "items"` — use `<plurals>`.
- **`String.format("%.2f", price)`** — use `NumberFormat.getCurrencyInstance()` instead.
- **`SimpleDateFormat` allocated per render.** Either inject a `DateTimeFormatter` or hold a thread-safe instance via `remember` / a singleton.
- **`stringResource(R.string.…)` outside a `@Composable`.** Use `context.getString(...)` in non-Compose code.
- **`left` / `right` in modifiers.** Use `start` / `end`.
- **Missing `android:supportsRtl="true"`.** Layouts won't mirror even if you used `start`/`end` correctly.
- **Bare `%s` / `%d` in multi-arg strings.** Use positional `%1$s`, `%2$d`.
- **No comments for translators.** They guess; you get bug reports in the wrong languages.
- **Region-specific overrides without language overrides.** `values-en-rGB/` only fires under exactly `en_GB`; if you also want `en_AU` and `en_CA`, you need either separate region files or the strings in `values-en/`.
- **Reading strings into Kotlin constants at startup.** That snapshots the user's locale at app launch — they won't update if the system language changes. Read fresh per-render.

## Patterns to Follow

```kotlin
// Composable — clean string usage
@Composable
fun SaveButton(
    onClick: () -> Unit,
    isSaving: Boolean
) {
    Button(onClick = onClick, enabled = !isSaving) {
        Text(
            text = stringResource(
                if (isSaving) R.string.settings_save_in_progress
                else R.string.settings_save_button
            )
        )
    }
}

// Plural — count passed twice (once for selection, once as a format arg)
@Composable
fun ItemCountLabel(count: Int) {
    Text(
        text = pluralStringResource(R.plurals.items_count, count, count),
        modifier = Modifier.semantics {
            contentDescription = pluralStringResource(R.plurals.items_count, count, count)
        }
    )
}

// Non-Compose — use Context
class FeedNotifier(private val context: Context) {
    fun message(senderName: String): String =
        context.getString(R.string.notifications_user_sent_message, senderName)

    fun itemCount(count: Int): String =
        context.resources.getQuantityString(R.plurals.items_count, count, count)
}
```

```xml
<!-- res/values/strings.xml -->
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!--
      Settings screen.
      Shown on the user's account preferences page.
    -->
    <string name="settings_save_button">Save</string>
    <string name="settings_save_in_progress">Saving…</string>

    <!--
      Notifications.
      %1$s is the sender's display name.
    -->
    <string name="notifications_user_sent_message">%1$s sent you a message.</string>
</resources>

<!-- res/values/plurals.xml -->
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <plurals name="items_count">
        <item quantity="one">%d item</item>
        <item quantity="other">%d items</item>
    </plurals>
</resources>
```
