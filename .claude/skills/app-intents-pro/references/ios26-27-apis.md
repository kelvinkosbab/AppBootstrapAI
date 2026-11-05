# App Intents in iOS 26 and iOS 27

> **Sources.** Apple App Intents documentation and Apple's Xcode 27 "What's new in App Intents" agent skill, published by [Artem Novichkov](https://github.com/artemnovichkov) in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills). Rewritten for this bundle. Availability below is iOS; the other platforms follow the same release (26.x, 27.x) unless noted.

Read the section before adopting an API. Several of these have close neighbors with different contracts, and memory tends to misdate them. When the deployment target is lower than the floor, gate with `@available` / `if #available` rather than dropping the feature.

| API | iOS | Notes |
|---|---|---|
| `supportedModes` / `IntentModes`, `continueInForeground`, `UndoableIntent` | 26.0 | replaces `openAppWhenRun` |
| `SnippetIntent`, `result(snippetIntent:)`, `requestChoice` | 26.0 | |
| `IntentValueQuery` + `SemanticContentDescriptor` (Visual Intelligence) | 26.0 | descriptor is macOS 27 |
| `@ComputedProperty` / `@DeferredProperty` | 26.0 | `indexingKey:` forms not on watchOS / tvOS |
| `CancellableIntent` | 26.4 | |
| `LongRunningIntent`, `allowedExecutionTargets` | 27.0 | |
| `IndexedEntityQuery`, `relatedAppEntityIdentifier` | 27.0 | not on watchOS / tvOS |
| `RelevantEntities`, `SyncableEntity`, `OwnershipProvidingEntity`, `EntityCollection`, `AppUnionValue`, `SystemShortcut` | 27.0 | `SystemShortcut` iPhone / iPad only |
| Schema macros `@AppIntent(schema:)` etc. | 18.0 | each domain has its own floor |
| Siri tools and generable entities | 27.3 | see `siri-integration.md` |

## Where the intent runs (26.0)

- `static var supportedModes: IntentModes` replaces `openAppWhenRun`. `.background` for headless work; `.foreground` (same as `.foreground(.immediate)`) to open the app before `perform()`; `.foreground(.deferred)` to start work and open when ready; `.foreground(.dynamic)` to decide at run time. It's an option set: `[.background, .foreground(.dynamic)]` starts headless and escalates.
- Escalate with `try await continueInForeground("…", alwaysConfirm: false)`, or `throw needsToContinueInForegroundError("…")` when the intent can't continue without the app. Check `systemContext.currentMode.canContinueInForeground` first: voice-only and some widget contexts can't open the app.
- `UndoableIntent` exposes a `@MainActor undoManager`; register the inverse action so the system can offer Undo. Touch it from a `@MainActor` `perform()`.
- `CancellableIntent` (26.4): wrap work in `withIntentCancellationHandler { … } onCancel: { reason in … }`; the reason is `.timeout` or `.userCancelled`.
- `LongRunningIntent` (27.0): outside macOS a background intent gets about 30 seconds. `performBackgroundTask(options:operation:)` hands work to a system background task that outlives the caller. It refines `ProgressReportingIntent`: set `progress.localizedDescription` and the unit counts, and the system shows them in a Live Activity. `.requiresGPU` when the work needs the GPU.
- `allowedExecutionTargets` (27.0): `.default` (system chooses), `.main`, `.appIntentsExtension`, `.widgetKitExtension`. Keep `.default` unless the code needs a specific process's live state; forcing `.main` adds launch latency.

## Interactive snippets (26.0)

- Model the card as a `SnippetIntent` whose `perform()` returns `.result(view:)`; the main intent returns `.result(snippetIntent:)` (with `value:` / `dialog:` as needed).
- Controls inside the view use `Button(intent:)` and `Toggle(isOn:intent:)` (iOS 17+), never closures, which run nothing in a snippet. Point them at a separate action intent, never at the snippet intent.
- The action intent does the mutation and returns `.result()`; the system re-runs the snippet's `perform()` and redraws. Use `.result(snippetIntent:)` only to show a snippet first or switch to a different one; call `YourSnippetIntent.reload()` for out-of-band updates.
- **`SnippetIntent.perform()` must be a pure read.** The system re-runs it on any redraw.
- Intents you construct with values (for `snippetIntent:` or `Button(intent:)`) need an `init` that assigns their parameters plus the empty `init()`.
- `requestConfirmation(actionName:snippetIntent:)` confirms with a custom card.
- Below 26, don't branch snippet styles inside one `perform()` (one opaque return type can't be two result types). Ship a separate gated intent.

## Choosing mid-run (26.0)

`try await requestChoice(between: options, dialog: "…")` returns the chosen `IntentChoiceOption`. Use it for a small fixed set decided during execution, not for entity selection. `.destructive` style for hard-to-undo options; including `IntentChoiceOption.cancel` makes a cancel **throw**.

## Apple Intelligence schemas (macros 18.0, domains vary)

- `@AppIntent(schema: .domain.action)`, `@AppEntity(schema:)`, `@AppEnum(schema:)` promise a fixed shape the system can invoke. The struct declares no `: AppIntent`; the macro adds it. A build tool validates the shape after compilation.
- **`@AssistantIntent` / `@AssistantEntity` / `@AssistantEnum` and `AssistantSchema` are deprecated** (renamed to the `@App*` forms). They still compile, with a warning. Swap the macro name; keep the `schema:` argument.
- Required properties and types come from the schema. Extra optional parameters appear only in Shortcuts; Siri never fills them.
- Surfaces: `audio`, `calendar`, `camera`, `clock`, `files`, `mail`, `maps`, `messages`, `notes`, `phone`, `photos`, `reminders`, `system` reach Apple Intelligence and Siri; `visualIntelligence` and `assistant` are single-purpose; `books`, `browser`, `journal`, `presentation`, `reader`, `spreadsheet`, `whiteboard`, `wordProcessor` are Shortcuts-only. `mail`, `clock`, and `messages` are all-or-nothing.
- A domain can have a later floor than the macro (`calendar` is 27.0, unavailable on watchOS / tvOS). Never emit a domain you haven't confirmed in the SDK.
- Migrating an intent whose shape would change: add a new schema intent with `static let isAssistantOnly = true` beside the old one, so saved shortcuts keep working and Shortcuts shows no duplicate.

## Visual Intelligence and "this" on screen

- Visual Intelligence (26.0): an `IntentValueQuery` with `Input == SemanticContentDescriptor` (`import VisualIntelligence`) returns matching entities from `values(for:)`. For several entity types, return a `@UnionValue` enum (gate the union type at 27.0) and give **each** concrete type its own `OpenIntent`.
- Onscreen entities (18.2+): set the foreground `NSUserActivity`'s `appEntityIdentifier = EntityIdentifier(for: entity)` for a detail screen, or use `.appEntityIdentifier(forSelectionType:_:)` (18.4) on list rows, so "add this to my list" resolves. The entity needs a working `defaultQuery`.

## Spotlight (`IndexedEntity` is 18.0)

- `@Property(indexingKey:)` (18.4), and on 26.0 `@ComputedProperty(indexingKey:)` / `@DeferredProperty(indexingKey:)` map values to `CSSearchableItemAttributeSet` keys.
- `@ComputedProperty` reads synchronously from the source of truth; `@DeferredProperty` is `get async throws` for expensive values. Both are read-only: never on `id` or editable state.
- `IndexedEntityQuery` (27.0) lets the system ask your query to reindex (`reindexEntities(for:indexDescription:)`, `reindexAllEntities(indexDescription:)`).
- `relatedAppEntityIdentifier` (27.0) links a `CSSearchableItem` you index yourself to an existing entity.

## Entities across devices, sharing, and large sets (27.0)

- `SyncableEntity` with `SyncableEntityIdentifier(local:stable:)` keeps identity across a person's devices. The query must handle an identifier that arrives with only one side.
- `OwnershipProvidingEntity.ownership: EntityOwnership` (`.shared`, `.public`) lets the system confirm before acting on data beyond the person's own. `.unknown` is the empty set, so "owned" and "unknown" look the same; set the bits that apply and leave it empty otherwise.
- `EntityCollection<Entity>` as a `@Parameter` or `@Property` carries ids and hydrates later with `resolvedEntities()` (cached). Iterating it yields ids. Avoids the full resolution a `[Entity]` parameter forces. `==` compares ids only.
- `AppUnionValue` makes a `@UnionValue` usable as a Shortcuts parameter.
- `RelevantEntities.shared.updateEntities(_:for:)` is **media-only**: playable items for `.audio(.nowPlaying)` or HealthKit workout contexts. It replaces the set per context; pair it with a removal. Don't confuse it with `RelevantIntent` (iOS 17, widget relevance).
- `SystemShortcut` + `RunSystemShortcutIntent` only backs a `Button(intent:)` inside a widget configuration.

## Review checklist

1. `openAppWhenRun` replaced with `supportedModes` where the target allows; foreground escalation guarded by `canContinueInForeground`?
2. Snippet `perform()`s side-effect free; controls point at separate action intents?
3. No `@Assistant*` macros; schema domains confirmed and gated at the domain's floor?
4. Every 26/27 API gated at its real floor; nothing Spotlight-related emitted for watchOS / tvOS?
5. `RelevantEntities` used only for media, with removals?
