# Multi-Module Graph

The standard non-trivial Android project layout, reference Now in Android:

```
:app                         ← @main entry point, scene wiring, DI graph completion
:feature:home                ← screen-feature modules
:feature:settings
:feature:profile
:data:repositories           ← repositories sit between features and the network/persistence
:data:network                ← Retrofit setup, API interfaces, response models
:data:persistence            ← Room database, DAOs, entities
:core:designsystem           ← Material theme, design tokens, atomic Composables
:core:ui                     ← shared composite Composables (cards, dialogs)
:core:common                 ← dispatchers, logging, base classes
:core:domain                 ← business-rule types, sealed states
:core:testing                ← MainDispatcherRule, MockData factories, test doubles
build-logic/convention/      ← convention plugins (not in :include, composite-built)
```

This is roughly NiA's shape. Adapt the granularity to project size: small apps merge `:core:ui` and `:core:designsystem`, large apps split `:feature:settings` further into `:feature:settings:account` and `:feature:settings:notifications`.

## Dependency direction (the most important rule)

Edges always point **toward** core and data. Features never depend on `:app` or on each other.

```
:app  →  :feature:*  →  :data:*
                    →  :core:*
:data:*  →  :core:*
:core:*  (leaf — depends on no first-party module)
build-logic/  (orthogonal — referenced via plugin application, not module dependency)
```

- **`:app` is the only module that depends on every `:feature:*`** — it composes them into the nav graph.
- **`:feature:*` modules never depend on each other.** Cross-feature navigation routes through a navigation contract in `:core:domain` or through `:app`'s NavHost.
- **`:data:*` modules never depend on `:feature:*` or `:app`.** Data is feature-agnostic.
- **`:core:*` modules never depend on anything but other `:core:*` modules** (and even that should be rare). They are the leaves.

When a feature module's `build.gradle.kts` reads `implementation(project(":feature:settings"))`, that's a smell — you've created cross-feature coupling. Either:
- The shared logic belongs in `:core:domain` or `:core:ui`.
- Or the two features should merge.

## Module shapes

Each module is one of a small number of shapes — the convention plugin you apply tells you which:

| Shape | Convention plugin | Examples |
|-------|-------------------|----------|
| App | `kozinga.android.application` (+ `kozinga.android.application.compose`) | `:app` |
| Feature (UI module with Compose + Hilt + ViewModel) | `kozinga.android.feature` | `:feature:home`, `:feature:settings` |
| Library (Compose-using, but not a feature screen) | `kozinga.android.library.compose` | `:core:ui`, `:core:designsystem` |
| Library (no UI) | `kozinga.android.library` | `:data:*`, `:core:common`, `:core:domain` |
| Pure-Kotlin (no Android dependencies) | `kozinga.jvm.library` | `:core:network-utils` if you have pure-Kotlin utilities |

The `kozinga.android.feature` convention plugin typically applies: `kozinga.android.library` + `kozinga.android.library.compose` + `kozinga.android.hilt` + common deps (`androidx.lifecycle.viewmodel.compose`, `hiltViewModel()`). Saves ~20 lines per feature module.

## `settings.gradle.kts` enumeration

Every module is `include(...)`'d:

```kotlin
include(":app")

include(":feature:home")
include(":feature:settings")
include(":feature:profile")

include(":data:repositories")
include(":data:network")
include(":data:persistence")

include(":core:designsystem")
include(":core:ui")
include(":core:common")
include(":core:domain")
include(":core:testing")
```

You can also use a `subprojectsOf("feature")` helper if you have many features and an explicit `subprojects.txt` for them, but for most teams, listing each is fine.

## When a feature module is too big

Symptoms:

- 30+ Kotlin files
- Multiple sub-screens
- Independent feature flags
- A reviewer needs to context-switch within a single PR

Refactor by splitting into:

```
:feature:settings
:feature:settings:account
:feature:settings:notifications
:feature:settings:privacy
```

Each sub-module is a screen or screen-group. The parent `:feature:settings` holds the screen graph + shared types; sub-modules hold the per-screen Composables + ViewModels.

## Cross-feature collaboration (without cross-feature deps)

When `:feature:profile` needs to navigate to `:feature:settings`:

- **Option A — Routes in `:core:domain`**: define a `SettingsRoute` enum in `:core:domain` that both features depend on. `:feature:profile` emits the route; `:app` translates the route to an actual navigation call.
- **Option B — Hilt-injected navigation contract**: a `Navigator` interface in `:core:domain`, implemented in `:app`, injected into every feature ViewModel. Features call `navigator.navigateTo(SettingsRoute.Account)` without knowing the destination implementation.

Either works. Pick one and use it everywhere.

## Common review findings

When reviewing a module graph:

- **A `:feature:*` depending on another `:feature:*`** — extract the shared bit, or merge.
- **A `:feature:*` depending on `:app`** — almost always wrong. `:app` depends on features, not the other way.
- **A `:data:*` depending on `:feature:*`** — also wrong.
- **A `:core:*` with feature-specific logic** — `:core:common` should not know about user profiles. Move feature-specific logic out.
- **All modules in a flat list without hierarchy** — `feature-home`, `feature-settings`, `data-repositories` instead of `:feature:home`, `:feature:settings`, `:data:repositories`. Use the colon-namespacing; it makes the graph readable.
- **A `:core:testing` that depends on production modules in non-test config** — should be `testImplementation`-scoped or use Gradle test fixtures.
- **Circular dependency** — Gradle catches these but the *reason* they emerged is usually a misplaced type in `:core:*`. Refactor.

## Module count vs build time

Each module is a Gradle target — too many means configuration overhead. Rough guidance:

- **5–10 modules**: sweet spot for small-to-mid apps.
- **10–30 modules**: typical for feature-rich apps; configuration cache and parallel build help.
- **30+ modules**: justified for large apps but watch incremental-build times. Sometimes merging tiny modules wins.

Don't fragment for fragmentation's sake. The goal is **clear ownership boundaries** and **independent buildability of features**, not module count.
