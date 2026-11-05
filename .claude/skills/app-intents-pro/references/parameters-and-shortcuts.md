# Parameters, summaries, localization, donation, and App Shortcuts

> **Sources.** Apple App Intents documentation and Apple's Xcode 27 App Intents agent skill, published by [Artem Novichkov](https://github.com/artemnovichkov) in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills). Rewritten for this bundle.

## Getting a missing value

- **`try await $param.requestValue("…")`** asks inline and returns the value. The rest of the same pass keeps running.
- **`throw $param.needsValueError("…")`** aborts and restarts `perform()` with the value filled (see the restart rules in `execution-and-results.md`). Use it only when a restart is what you want.
- The old `requestValue(_:) -> Error` overload that you `throw` is deprecated. If you're throwing what `requestValue` returns, you're on it.
- A non-optional **`AppEnum`** parameter doesn't throw a needs-value error when empty: the framework shows a picker (or silently assigns the only case). Its prompt comes from `requestDisambiguationDialog:`, not `requestValueDialog:`.

## Options that depend on another parameter

Inside an `EntityQuery` or `DynamicOptionsProvider`, the intent's other parameters aren't resolved yet and there's no intent instance to read. Declare the dependency and read it through the projection:

```swift
struct AisleQuery: EntityStringQuery {
    @IntentParameterDependency<AddToListIntent>(\.$store)
    var addToList

    func entities(matching text: String) async throws -> [AisleEntity] {
        guard let addToList else { return [] }      // store not chosen yet
        return try await Aisles.in(addToList.store, matching: text)
    }
    func entities(for ids: [AisleEntity.ID]) async throws -> [AisleEntity] {
        try await Aisles.with(ids)
    }
}
```

Reading a key path you didn't list in the dependency traps, so list every parameter you read.

## Parameter summaries

`static var parameterSummary` is the **allowlist** for the Shortcuts editor: a parameter neither interpolated into `Summary("…")` nor listed in its trailing block doesn't appear at all.

```swift
static var parameterSummary: some ParameterSummary {
    Summary("Add \(\.$item) to \(\.$list)") {
        \.$quantity
        \.$note
    }
}
```

- Field order follows the summary (interpolations, then the block), not declaration order.
- `When(\.$p, .equalTo, value) { … } otherwise: { … }` shows or hides parameters by another one's value. The comparator types differ: `.equalTo` / `.notEqualTo` take a value, `.hasAnyValue` / `.hasNoValue` take none, `.oneOf` takes an array.
- `Switch(\.$p) { Case(v) { … } DefaultCase { … } }` for several discrete values; always include `DefaultCase`.
- Write a literal `%` once; interpolation escapes it.
- Omitting a parameter from the summary is fine when it's only ever filled programmatically, but make it a deliberate choice.

## Localization

Every user-facing slot (`title`, `IntentDescription`, `DisplayRepresentation`, `TypeDisplayRepresentation`, `IntentDialog`, `@Parameter(title:)`, App Shortcut phrases and `shortTitle`) is a `LocalizedStringResource`, and its key is **extracted from the source literal at build time**.

- A `LocalizedStringResource` built from a runtime `String` (`LocalizedStringResource(stringLiteral: name)`, `"Recipe: " + name`) has no extractable key. It shows in English and never translates.
- Interpolate data into a literal template: `"Delete \(count) items"`. For counted entity names use `TypeDisplayRepresentation(name: "Recipe", numericFormat: "\(placeholder: .int) recipes")` with plural variants in the catalog.
- A user-authored name (a recipe title) is data, so `DisplayRepresentation(title: "\(name)")` is correct.
- App Shortcut phrases live in their own catalog, `AppShortcuts.xcstrings`, separate from `Localizable.xcstrings`.

## Donation

- The system donates only the intents *it* runs (Siri, Shortcuts). An action the person takes in your own UI is **not** donated unless you do it, and prediction (Siri Suggestions, Spotlight) learns nothing from it.
- After the in-app action succeeds, `try? await IntentDonationManager.shared.donate(intent: …)`; use `donate(intent:result:)` when the intent returns a value. Don't donate from inside `perform()` (that double-counts).
- The throwing async overload tells you whether it landed; the synchronous one is fire-and-forget. Delete donations when the data behind them is deleted.
- `PredictableIntent` only supplies suggestion display text. It isn't the donation hook.

## App Shortcut phrases

- Use the `AppShortcut` initializer with **`shortTitle` and `systemImageName`**; the one without them is deprecated (iOS 17) and leaves a blank tile. `systemImageName` must be a string literal naming a real SF Symbol.
- **Every phrase contains `\(.applicationName)`.** Xcode warns at build time, and the runtime index drops phrases without it. Register app-name synonyms with `INAlternativeAppNames` in Info.plist (at most three per localization; `INPreferredForAppShortcuts` picks the preferred one).
- Interpolate only parameters with a closed, named set of options: an `AppEnum`, an `AppEntity`, or a `Bool` that supplies `displayName: Bool.IntentDisplayName(true:false:)`. Free-form strings, numbers, and dates give Siri nothing to match.
- At most **10 App Shortcuts** per app; the build fails above that. Phrases have a per-locale budget (about 1,000 *expanded* phrases, where each enum case or entity option counts). Don't list minor wording variants: Siri matches flexibly, and near-duplicates make matching worse. Check with **Product ▸ App Shortcuts Preview**.
- When the options behind a dynamic phrase parameter change (a new list, a deleted recipe), call `YourShortcuts.updateAppShortcutParameters()`.
- Renaming or removing a shipped phrase breaks voice invocation and habits (saved shortcuts survive, since they run the intent by type). Add phrases; don't rewrite them.

## Opening content

- **`OpenIntent`** adds a `target`, foregrounds the app, and supplies a default `perform()`. Don't hand-roll foregrounding. Its `perform()` still isn't `@MainActor`.
- **`OpenURLIntent(url)`**, returned through `OpensIntent`, opens a universal link; also the intent behind widget and Live Activity deep-link buttons.
- **`URLRepresentableIntent` / `URLRepresentableEntity` / `URLRepresentableEnum`** map a type to a universal link so the system opens it without running your `perform()`. Build `urlRepresentation` by interpolating parameter **key paths** (`"https://example.com/recipes/\(\.$recipe)"`). It needs real universal links (`applinks:`), not a custom scheme. The URL shape is a contract like ids: evolve it additively.

## Widget and control configuration

- `WidgetConfigurationIntent` (iOS 17) and `ControlConfigurationIntent` (iOS 18) only describe configuration: their `@Parameter`s become the editing fields. They need **no** `perform()`; writing one doesn't activate anything.
- The action a control runs is a separate intent; a toggle control's action is a `SetValueIntent`, which does implement `perform()`.

## Review checklist

1. `requestValue` where the value is needed inline; `needsValueError` only where a restart is intended?
2. Enum parameters have `requestDisambiguationDialog`?
3. Cross-parameter options go through `@IntentParameterDependency`?
4. Every user-configurable parameter in the summary; `DefaultCase` on every `Switch`?
5. All user-facing strings are source literals?
6. In-app actions donated after they succeed?
7. Every App Shortcut has `shortTitle`, `systemImageName`, and `\(.applicationName)` in each phrase; at most 10 shortcuts?
8. No `perform()` on configuration intents?
