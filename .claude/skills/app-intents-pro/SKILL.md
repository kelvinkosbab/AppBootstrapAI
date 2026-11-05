---
name: app-intents-pro
description: Writes and reviews App Intents for Shortcuts, Siri, Spotlight, widgets, and controls — perform() isolation and restarts, stable AppEntity ids and batched queries, AppEnum raw values, parameters and summaries, @Dependency registration, errors Siri can show, donation, App Shortcut phrases, the iOS 26/27 APIs (supportedModes, interactive snippets, schemas, Spotlight indexing, EntityCollection, AppIntentsTesting), and Siri's model in 27.3 (@AppIntent(.tool), generable entities, Skills.skillsbundle, sirimetadataanalyzer, SiriEvaluations). Use when writing, reviewing, or migrating App Intents code, or making an app work with Siri or Apple Intelligence.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "Apple App Intents documentation and the App Intents, Siri app integration, and SiriEvaluations agent skills Apple ships with Xcode 27 (as published by Artem Novichkov in artemnovichkov/xcode-skills)"
---

Write and review App Intents code. This is the deep-review companion to the `apple-app-intents.md` rule: the rule steers while writing; this skill audits whole intent surfaces and drives Siri adoption. Report only genuine problems.

> **Sources.** Grounded in Apple's App Intents documentation and in the App Intents, Siri app integration, and SiriEvaluations skills Apple bundles with Xcode 27, which [Artem Novichkov](https://github.com/artemnovichkov) extracted and published in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills). The guidance is rewritten and condensed for this bundle, not copied. Check spellings and availability against the SDK you build with.

If asked to **write or fix** rather than review, make the changes directly and summarize them in the same file-by-file format.

Review process:

1. Check `perform()` isolation, restart safety, confirmation order, and result and error shapes using `references/execution-and-results.md`.
2. Check entity identity, queries, enums, and `@Dependency` placement using `references/entities-and-queries.md`.
3. Check parameters, parameter summaries, localization, donation, and App Shortcut phrases using `references/parameters-and-shortcuts.md`.
4. When the deployment target or SDK is 26 or later, or the code uses any newer API, check adoption and availability gating using `references/ios26-27-apis.md`.
5. When the task is Siri or Apple Intelligence (tools, generable entities, app skills for Siri), follow `references/siri-integration.md`.
6. For tests, use `references/testing-and-evaluation.md` (`AppIntentsTesting` for intents and queries, `SiriEvaluations` for how Siri uses them).

On a large codebase, list the intent surfaces first (each intent, entity and its query, enum, the `AppShortcutsProvider`) and review them one at a time. For a partial review, load only the matching reference.

## Core Instructions

- **Identifiers are a public contract.** Saved shortcuts and donations replay an intent by its type name and store `AppEntity.id`s and `AppEnum` raw values. App Shortcut phrases are a separate contract for voice. Adding is safe. Renaming or removing an intent type, changing an id scheme, renumbering an enum, or adding, removing, or renaming a parameter breaks users' shortcuts: flag it and never do it as a side effect.
- **Public API only.** Never emit underscore-prefixed or private symbols, and never invent a type, initializer, or parameter to make a snippet compile. If a capability needs non-public API, say so.
- **Gate by real availability.** Tag each newer API with its true floor (the references list them) and gate with `@available` / `if #available` when the deployment target is lower. Don't drop the feature and don't misdate it.
- **Keep `perform()` thin.** It calls the app's existing model code and writes to the persisted store. An intent can run while the app isn't on screen, and the process can exit right after, so in-memory-only state is lost.
- **Severity by user impact**: crash or data loss (unregistered `@Dependency`, missing `caseDisplayRepresentations` entry, double-charge on restart, broken saved shortcuts) > broken surface (empty picker, untranslatable strings, generic error message, dropped phrase) > polish (missing search keywords, weak descriptions).
- Cross-reference, don't duplicate: actor isolation belongs to `swift-concurrency-pro`; error type design to `swift-error-handling-pro`; String Catalog structure to the `apple-localization-best-practices.md` rule; Swift Testing style to `swift-testing-pro`.

## Output Format

Organize findings by file. For each issue: file and line, the violated principle, the user-visible consequence, and a brief before/after. Skip clean files. End with a prioritized summary.

Example finding:

### LogWorkoutIntent.swift

**Line 31: the charge runs before `needsValueError`, so a missing value restarts `perform()` and charges twice.**

```swift
// Before
try await billing.charge(plan)
guard let card else { throw $card.needsValueError("Which card?") }

// After
guard let card else { throw $card.needsValueError("Which card?") }
try await billing.charge(plan, to: card)
```

### Summary

1. **Crash or data loss:** `RecipeQuery` reads an unregistered `@Dependency` on a cold Siri launch.
2. **Broken surface:** `MealKind` has no display entry for `.brunch`; Shortcuts traps when it shows the case.
3. **Polish:** two App Shortcuts lack `shortTitle` and `systemImageName`.

End of example.

## References

- `references/execution-and-results.md` — `perform()` isolation, restarts and idempotency, confirmation, `.result(...)` shapes, errors Siri and Shortcuts can show.
- `references/entities-and-queries.md` — stable ids, `@Property` visibility, `entities(for:)` vs `suggestedEntities()`, string and property queries, `EnumerableEntityQuery` limits, `AppEnum` persistence, `@Dependency` registration and placement.
- `references/parameters-and-shortcuts.md` — `requestValue` vs `needsValueError`, enum disambiguation, `@IntentParameterDependency`, parameter summaries, localization, donation, App Shortcut phrases, URL and configuration intents.
- `references/ios26-27-apis.md` — `supportedModes`, foreground continuation, undo, cancel, long-running intents, execution targets, interactive snippets, `requestChoice`, schemas, Visual Intelligence, onscreen entities, Spotlight indexing, relevant entities, syncable and ownership-aware entities, `EntityCollection`, union values.
- `references/siri-integration.md` — making an app work with Siri's model in 27.3: adoption order, `@AppIntent(.tool)`, metadata the model reads, generable entities, property descriptions and `.internal`, the app's `Skills.skillsbundle`, `sirimetadataanalyzer`.
- `references/testing-and-evaluation.md` — `AppIntentsTesting` (out-of-process intent and query tests) and `SiriEvaluations` (scenarios that grade how Siri picks and fills intents).
