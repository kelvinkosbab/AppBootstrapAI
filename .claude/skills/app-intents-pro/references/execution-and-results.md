# How `perform()` runs, and what it returns

> **Sources.** Apple App Intents documentation and Apple's Xcode 27 App Intents agent skill, published by [Artem Novichkov](https://github.com/artemnovichkov) in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills). Rewritten for this bundle.

The naive model of an intent is "a function in my running app, on the main thread, called once." All three parts are wrong, and each one has its own bug.

## Not on the main actor

`AppIntent` is `Sendable` and `perform()` has no actor annotation. It can run off the main thread, and in an App Intents extension rather than the app.

- Touching a `@MainActor` view model, navigator, or UIKit / AppKit object directly from `perform()` is a data race (a compile error under Swift 6). Hop explicitly: `await MainActor.run { … }`, `await` a `@MainActor` method, or annotate the method itself: `@MainActor func perform() async throws -> some IntentResult` when most of the body is UI work.
- Don't mark the intent **type** `@MainActor`. The protocol's requirements (`title`, parameters) are nonisolated, so the conformance doesn't compile in its plain form, and forcing it pins parameter resolution to the main actor too.

```swift
struct ShowRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Recipe"
    @Parameter(title: "Recipe") var recipe: RecipeEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.show(recipe.id)   // Router is @MainActor
        return .result()
    }
}
```

## It can run more than once

`$param.needsValueError(_:)` and `AppIntentError.restartPerform` abort the current pass and run `perform()` again **from the top**. Nothing you committed on the first pass is rolled back.

- Resolve and validate everything first. Do irreversible work (charging, sending, deleting, appending to a log) last, after nothing else can trigger a restart. If a restart is still possible around it, guard it with an idempotency key so a replay is a no-op.
- Restarts and value requests are expected control flow. Don't catch and swallow them as failures.

## Confirm before the destructive step

`requestConfirmation(...)` suspends inside the same pass, returns if the person confirms, and **throws** if they cancel. So it goes immediately *before* the irreversible action, and the cancel aborts `perform()` by itself.

- Confirming after the work is theater. Wrapping the call in `try?` or `do/catch` makes cancel behave like confirm.
- The dialog-bearing `requestConfirmation(conditions:actionName:dialog:)` is iOS 18+; the parameterless form is iOS 16+.

## Return through `.result(...)`

`perform()` returns `some IntentResult` built with the `.result(...)` factories, composed with the markers you actually use: `ReturnsValue<T>`, `ProvidesDialog`, `OpensIntent`, `ShowsSnippetView`.

```swift
func perform() async throws -> some ReturnsValue<Int> & ProvidesDialog {
    let count = try await store.countDue()
    return .result(value: count, dialog: "You have \(count) tasks due.")
}
```

- Never return a domain type directly, and never name `IntentResultContainer`.
- `OpensAppIntent` is the deprecated spelling; use `OpensIntent`.
- Return a value when something downstream (a Shortcuts step, Siri's next tool call) needs it. `.result()` alone gives the caller nothing to continue with.

## Errors that reach the person

Siri and Shortcuts pick the message by the **type** of the error you throw.

- Only errors conforming to `CustomLocalizedStringResourceConvertible` surface their message. A plain `Error`, *including* a `LocalizedError` with an `errorDescription`, shows as a generic failure.

```swift
enum PantryError: Error, CustomLocalizedStringResourceConvertible {
    case outOfStock(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .outOfStock(let item): "\(item) is out of stock. Pick another ingredient."
        }
    }
}
```

- For standard cases, throw the prebuilt errors (iOS 18+), which carry a localized message *and* a category Siri understands (for example, it can offer sign-in): `AppIntentError.UserActionRequired.signin`, `AppIntentError.PermissionRequired.photos`, `AppIntentError.Unrecoverable.entityNotFound`. `AppIntentError.Unrecoverable.unknown` is deprecated; name the real failure.
- Say what went wrong and what would fix it. Siri's model reads the message and can recover ("that store doesn't deliver on Sundays" lets it ask for another day).
- The same routing applies to errors thrown from `EntityQuery` methods.

## Review checklist

1. Any `@MainActor` state touched from a nonisolated `perform()`? Any `@MainActor` on an intent type?
2. Any side effect before a `needsValueError`, `restartPerform`, or a parameter that may still need a value?
3. Every destructive action preceded by `requestConfirmation`, and the cancel left to propagate?
4. Results built with `.result(...)`, with only the markers used?
5. Thrown errors conform to `CustomLocalizedStringResourceConvertible` or use a prebuilt `AppIntentError`?
