# Testing intents and evaluating Siri

> **Sources.** Apple's Xcode 27 App Intents and Siri evaluations agent skills, published by [Artem Novichkov](https://github.com/artemnovichkov) in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills), and Apple's AppIntentsTesting and SiriEvaluations documentation. Rewritten for this bundle. Verify symbols against the SDK.

Three layers, cheapest first: unit tests of the logic `perform()` calls, `AppIntentsTesting` against the installed app, and SiriEvaluations for how Siri's model uses the tools.

## Unit tests (any OS)

- Keep `perform()` thin so the logic behind it is a plain type with Swift Testing tests (`apple-testing-strategy.md`).
- Test the `AppEnum` contract: every case has a display entry (iterate `allCases`) and raw values match a frozen list.
- Test queries directly: `entities(for:)` with a mix of live and deleted ids, and `suggestedEntities()` returns a bounded, non-empty result for seeded data.

## `AppIntentsTesting` (27.0)

Runs **out of process** against the installed app, the way Siri and Shortcuts call it.

```swift
import AppIntentsTesting
import Testing

@Suite struct ShoppingIntentTests {
    let definitions = IntentDefinitions(bundleIdentifier: "com.example.Pantry")

    @Test func addingAnIngredientReturnsTheItem() async throws {
        let intent = try definitions.intents["AddToShoppingList"]
            .makeIntent(ingredient: definitions.entities["IngredientEntity"].makeReference(identifier: "flour"),
                        quantity: 2)
        let result = try await intent.run()
        let item = try result.value.as(AnyAppEntity.self)
        #expect(item.identifier.instanceIdentifier == "flour")
    }
}
```

- `import AppIntentsTesting` only in test targets. Pass the **app's** bundle id, not the test bundle's.
- Intents and entities are looked up by type name; `makeIntent(...)` takes the real parameter labels; `makeReference(identifier:)` builds an entity reference by id.
- `run()` returns a `ResolvedIntentResult`; `value` throws when the intent returned none; `.as(_:)` converts. Entity queries come back as `AnyAppEntity`. `values(for:)` exercises an `IntentValueQuery`, `spotlightQuery(_:)` the Spotlight path (not tvOS / watchOS), `viewAnnotations()` the onscreen entities (needs an `XCUIApplication` running).
- There's no in-process dependency injection. Add debug-only seed and reset intents to put the app in a known state, and call them from test setup.
- The import can't be gated, so gate usage with `@available` on suites when the test target supports older OSes.

## SiriEvaluations (27.3)

Measures whether Siri picks the right tools and fills parameters correctly. Do **one stage at a time** and show the developer the result before the next.

1. **Write scenarios**: requests in people's words with the expected tool calls, loaded with `SiriScenarioLoader` and run through `SiriService.run(scenario:)` inside tests that use `.evaluates(…)` traits. Cover the main tasks, look-alike tools, missing parameters (Siri should ask), and requests the app shouldn't handle.
2. **Run** on a **device** with Apple Intelligence; the simulator can't host the model. Run after a fresh build, since stale metadata gives stale results.
3. **Analyze** the reports in the `.xcresult` (under DerivedData `Logs/Test`). Fix metadata first (titles, descriptions, parameter text, skills), rerun `sirimetadataanalyzer`, then re-evaluate. Don't edit scenarios to make a failure pass.

Results are probabilistic: track pass rates across runs, not single outcomes.

## Review checklist

1. Logic behind `perform()` unit tested; enum and query contracts tested?
2. Intent end-to-end tests with `AppIntentsTesting`, seeded through debug intents?
3. Siri tools covered by scenarios for look-alikes and missing parameters, run on device after a fresh build?
