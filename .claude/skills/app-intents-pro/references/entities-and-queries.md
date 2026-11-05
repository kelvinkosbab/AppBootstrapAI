# Entities, queries, enums, and dependencies

> **Sources.** Apple App Intents documentation and Apple's Xcode 27 App Intents agent skill, published by [Artem Novichkov](https://github.com/artemnovichkov) in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills). Rewritten for this bundle.

An `AppEntity` is a reference the system stores, not a value it copies. A saved shortcut keeps the entity's `id`, and days later, maybe on another device, hands that id back to your query. Most entity bugs come from forgetting that.

## Factoring: enum, entity, or parameter

- **`AppEnum`**: a fixed set known at compile time (meal kind, priority).
- **`AppEntity` + `EntityQuery`**: dynamic, user-created, or queryable data (recipes, lists, documents).
- **Plain `@Parameter`** (`String`, `Int`, `Date`, …): free-form input.
- Prefer one intent per atomic task over a mega-intent with a mode switch, unless the actions share parameters and every mode is clearly described (see `siri-integration.md`).

## Stable ids

- The `id` must survive launches, reinstalls, and devices: a server key or a UUID minted once and stored with the record. Never an array index, a Photos `localIdentifier`, a local row id, or `UUID()` generated at launch (common in seed data). An unstable id makes `entities(for:)` return nothing and the shortcut breaks silently.
- `String`, `UUID`, and `Int` already conform to `EntityIdentifierConvertible`. A custom id type implements it and keeps the string under 4,096 characters.
- If the local id genuinely differs per device, that's the cross-device case: see `SyncableEntity` in `ios26-27-apis.md`.

## What the system can see

- Only `@Property` (and, on 26+, `@ComputedProperty` / `@DeferredProperty`) members are visible to Find actions, property queries, Siri, and display. A plain `var` compiles and stays invisible. Keep plain `var`s for values that only feed `displayRepresentation`.
- `displayRepresentation` is how people and Siri tell results apart: a title that names the thing and a subtitle that separates look-alikes. Never show a UUID or database id.

## The query's two jobs

- **`entities(for:)`** (required) resolves ids the system already holds. It takes an array: run **one** batched fetch, never a fetch per id. Return fewer entities than requested when some are gone; the framework drops missing ids and reorders the rest.
- **`suggestedEntities()`** fills the picker when there's no id yet. Its default returns `[]`, so a query that implements only `entities(for:)` compiles, resolves saved values, and shows an **empty picker**. Implement it, and keep it cheap and bounded (`limit:`): the system calls it opportunistically.
- **`EntityStringQuery.entities(matching:)`** gets the raw search text. The framework doesn't filter for you; your query does the match.
- **`EntityPropertyQuery`** powers "Find recipes where…": declare `properties` and `sortingOptions`, implement `entities(matching:mode:sortedBy:limit:)`. The framework parses the predicate; your data layer runs it.
- **`EnumerableEntityQuery`** (iOS 17+) is ergonomic but calls `allEntities()` and filters in memory. Fine for a small bounded set (a person's lists or accounts). For a large or growing store, use `EntityPropertyQuery`, or `IndexedEntity` for Siri (see `siri-integration.md`).

## `AppEnum`

- The raw value's **string form** is what gets persisted, not the case name or position. Give every case an explicit raw value, never reorder or renumber shipped values, and only append. Deleting a case orphans shortcuts that use it.

```swift
enum MealKind: String, AppEnum {
    case breakfast = "breakfast"
    case lunch = "lunch"
    case dinner = "dinner"
    case brunch = "brunch"   // appended later: safe

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Meal"
    static let caseDisplayRepresentations: [MealKind: DisplayRepresentation] = [
        .breakfast: "Breakfast",
        .lunch: "Lunch",
        .dinner: "Dinner",
        .brunch: "Brunch",
    ]
}
```

- `caseDisplayRepresentations` is a plain dictionary, so the compiler doesn't check it covers every case. A missing entry is a **runtime trap** when that case is displayed. New case, raw value, and display entry go in the same edit.
- Display text can change and be localized; raw values are frozen.

## `@Dependency`

The system builds intents and queries itself, so dependencies come from one shared registry, `AppDependencyManager.shared`.

- **Register in `App.init()`** (or the extension's one-time setup), which runs on every launch, including the cold, headless launches Siri and Spotlight cause. Registering in `.onAppear` or on first use means the first cold invocation hits an unregistered dependency, which is a `fatalError`, not a catchable error. Use the `default:` overload when a dependency can legitimately be absent.
- **Only intents, `DynamicOptionsProvider`s, and `EntityQuery`s get dependencies resolved.** On an `AppEntity` or `AppEnum` the wrapper compiles and is never prepared. Data access belongs in the entity's query.
- **The value must be `Sendable`.** A plain `@Observable final class` store isn't, and storing it makes the intent ill-formed under Swift 6. Isolate the store to `@MainActor` (which makes it `Sendable`) or make it an `actor`.

```swift
@main
struct RecipesApp: App {
    init() {
        AppDependencyManager.shared.add(dependency: RecipeStore.shared)  // actor or @MainActor
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

## Review checklist

1. Every entity id stable across launches and devices?
2. Every system-visible value wrapped in `@Property`; display representations specific?
3. `entities(for:)` batched; `suggestedEntities()` implemented and bounded?
4. `EnumerableEntityQuery` only over small sets?
5. Every `AppEnum` case has an explicit raw value and a display entry?
6. Every `@Dependency` registered in `App.init()`, placed on an intent or query, and `Sendable`?
