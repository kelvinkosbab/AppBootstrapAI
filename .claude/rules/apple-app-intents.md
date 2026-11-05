---
description: App Intents, App Shortcuts, and Siri tools — nonisolated perform(), restart-safe side effects, confirmation before destructive work, stable entity ids and frozen enum raw values, batched queries, typed user-facing errors, App Shortcut phrase rules, supportedModes over openAppWhenRun, schema macros, and Siri 27.3 tool metadata
globs: "**/*{Intent,Entity,Shortcut,Query}*.swift"
paths:
  - "**/*{Intent,Entity,Shortcut,Query}*.swift"
must:
  - "perform() is not on the main actor: hop to MainActor for UI state and never mark the intent type @MainActor."
  - "Entity ids and AppEnum raw values are persisted contracts: stable across launches and devices, append-only."
  - "Do irreversible work last, right after requestConfirmation, and let a cancel propagate."
  - "Throw CustomLocalizedStringResourceConvertible or prebuilt AppIntentError errors so the message reaches the person."
  - "Every App Shortcut phrase includes the application name; at most 10 App Shortcuts."
---

# App Intents

App Intents power Shortcuts, Siri, Spotlight, widgets, controls, and the Action button, and in 27.3 Siri's model calls them as tools. The system builds intents itself, may run them in an extension, restarts them, and stores entity references for years, so code that looks like an ordinary function call breaks in quiet ways. The `app-intents-pro` skill reviews and builds intents in depth.

> **Sources.** Apple's App Intents documentation and Apple's Xcode 27 App Intents, What's New in App Intents, and Siri app integration agent skills, as published by [Artem Novichkov](https://github.com/artemnovichkov) in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills). Rewritten in this bundle's words; nothing is copied.

## Core Rules

### Execution
- `perform()` is nonisolated and may run off the main thread or in an extension. Reach `@MainActor` state with `await MainActor.run`, an awaited `@MainActor` method, or `@MainActor func perform()`. Never `@MainActor` on the intent type.
- `needsValueError` and `restartPerform` rerun `perform()` from the top without rolling anything back. Resolve and validate first; side effects last.
- `requestConfirmation` goes immediately before the destructive step. Never wrap it in `try?`; the throw is how cancel aborts.
- Return through `.result(...)` with only the markers you use (`ReturnsValue`, `ProvidesDialog`, `OpensIntent`, `ShowsSnippetView`). `OpensAppIntent` is deprecated.
- Prefer `static var supportedModes` (26+) over the deprecated `openAppWhenRun`; check `systemContext.currentMode.canContinueInForeground` before escalating.

### Entities and enums
- Entity ids survive launches, reinstalls, and devices. No array indexes, launch-time `UUID()`, or Photos local identifiers.
- Only `@Property` (and 26+ `@ComputedProperty` / `@DeferredProperty`) members are visible to the system.
- `entities(for:)` runs one batched fetch. Implement a bounded `suggestedEntities()` or the picker is empty. `EnumerableEntityQuery` only over small sets.
- `AppEnum` cases get explicit raw values, are only appended, and each has a `caseDisplayRepresentations` entry (a missing one traps at runtime).
- Register `@Dependency` values in `App.init()`, use them only on intents, queries, and options providers, and make them `Sendable`.

### Errors and strings
- Only `CustomLocalizedStringResourceConvertible` errors show their message; a `LocalizedError` shows a generic failure. Use prebuilt `AppIntentError` cases (iOS 18+) for sign-in, permissions, and missing entities.
- Every user-facing string is a source literal so its key is extracted; never build a `LocalizedStringResource` from a runtime `String`.

### App Shortcuts
- `AppShortcut` with `shortTitle` and `systemImageName`; `\(.applicationName)` in every phrase; only closed-set parameters (`AppEnum`, `AppEntity`) in phrases; at most 10 shortcuts. Add phrases, don't rewrite shipped ones.
- Donate in-app actions with `IntentDonationManager` after they succeed, not from `perform()`.

### Schemas and Siri (27.3)
- Use `@AppIntent(schema:)` / `@AppEntity(schema:)` / `@AppEnum(schema:)`; the `@Assistant*` macros are deprecated.
- Check for a matching schema before adding `@AppIntent(.tool)`; primary-domain schema intents can't be tools.
- No search or find tools; make entities findable with `IndexedEntity`. Describe every tool, parameter, and exposed property; hide sensitive properties with `visibility: .internal`.
- Run `xcrun sirimetadataanalyzer` on a fresh build after every metadata change.

## Patterns to Follow

```swift
struct DeleteListIntent: AppIntent {
    static let title: LocalizedStringResource = "Delete List"
    @Parameter(title: "List") var list: ListEntity
    @Dependency var store: ListStore           // actor, registered in App.init()

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requestConfirmation(actionName: .delete, dialog: "Delete \(list.name)?")
        try await store.delete(list.id)         // irreversible, last
        return .result(dialog: "Deleted \(list.name).")
    }
}
```
