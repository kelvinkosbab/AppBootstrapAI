---
description: Structure Android apps as a thin :app module over many small Gradle modules (feature, data, domain, model, core) — why it wins, module types and allowed edges, cross-feature navigation, Hilt and resources across modules, enforcing the graph, and migrating a monolith incrementally
globs: "**/settings.gradle.kts,**/build.gradle.kts,**/*.kt"
---

# Android Modular Architecture

The target shape is a **thin `:app` module** that wires things together, on top of **many small Gradle modules** where the real app lives: one per feature, plus shared data, domain, model, and core modules. It is the Android counterpart of [`apple-modular-architecture.md`](./apple-modular-architecture.md), and the module names line up so a two-platform team can reason about one graph (see [`cross-platform-development.md`](./cross-platform-development.md)).

This rule covers the *architecture decision* and *migration*. Build mechanics live elsewhere: Gradle DSL, version catalogs, and the module list in [`android-gradle-conventions.md`](./android-gradle-conventions.md), and `build-logic` convention plugins in the **`android-gradle-architecture-pro`** skill. To plan a module graph, audit one, or migrate a monolith step by step, invoke the **`android-modularization-pro`** skill.

> **Reference layout: [Now in Android](https://github.com/android/nowinandroid).** Google's reference app splits into `:app`, `:feature:*` (with an `api`/`impl` split), `:core:data`, `:core:domain`, `:core:model`, `:core:database`, `:core:network`, `:core:datastore`, `:core:designsystem`, `:core:ui`, `:core:testing`, and `:sync`, all configured through `build-logic` convention plugins.

## Why modularize

- **Build speed.** Gradle compiles modules in parallel and skips modules whose inputs didn't change. With `implementation` edges, a change inside a feature recompiles that feature and `:app`, not the world. Build cache and configuration cache multiply the win.
- **Enforced boundaries.** A module sees only what it declares and what other modules expose. Kotlin `internal` becomes a real wall, so layering violations become compile errors.
- **Faster, focused tests.** `./gradlew :feature:tasks:impl:testDebugUnitTest` runs one feature's tests. Fakes live in one shared `:core:testing`.
- **Ownership and review.** A module is a unit a team (or an agent) can own, change, and test without reading the rest of the app.
- **Reuse.** Wear OS, TV, widgets, and an instant app link the same `:core:*` and feature modules. Code in `:app` reaches none of them.
- **Play Feature Delivery.** Dynamic feature modules are only possible once features are modules.

## Module types

| Type | Example | Contains | May depend on |
|---|---|---|---|
| **App** | `:app` | `Application`, `MainActivity`, the top-level `NavHost`, Hilt entry point, manifest, launcher icon | everything it assembles |
| **Feature** | `:feature:tasks` (or `:feature:tasks:api` + `:feature:tasks:impl`) | screens, ViewModels, the feature's nav graph | `:core:*`, other features' `api` only |
| **Data** | `:core:data` | repositories and their Hilt bindings | `:core:database`, `:core:network`, `:core:datastore`, `:core:model` |
| **Domain** (optional) | `:core:domain` | use cases reused across features | `:core:data`, `:core:model` |
| **Model** | `:core:model` | plain domain `data class`es, IDs; pure Kotlin/JVM | nothing |
| **Data sources** | `:core:database`, `:core:network`, `:core:datastore` | Room, Retrofit, DataStore | `:core:model`, `:core:common` |
| **Design system** | `:core:designsystem` | `AppTheme`, tokens, `AppIcons`, components | Compose + M3 only (see [`android-design-system.md`](./android-design-system.md)) |
| **Shared UI** | `:core:ui` | composables that take domain models (a task row) | `:core:designsystem`, `:core:model` |
| **Common** | `:core:common` | dispatcher qualifiers, `Result` helpers, logging setup | nothing app-specific |
| **Testing** | `:core:testing` | fakes, `MainDispatcherRule`, test runner | the modules it fakes |

- **`:core:model` is pure Kotlin** (`kotlin("jvm")`, no Android plugin). It builds fastest and every layer can use it.
- **Start with what you need.** A new app can begin with `:app`, `:core:model`, `:core:data`, `:core:designsystem`, and one feature, and split further when real boundaries appear.

## Dependency rules

- **The graph flows one way**: `:app` → features → `:core:domain` → `:core:data` → data sources → `:core:model`. Nothing points back up.
- **Features never depend on another feature's implementation.** If two features need the same thing, it moves down into `:core:*`. With an `api`/`impl` split, a feature may depend on another feature's `:api` module (routes and small contracts), never its `:impl`.
- **Only `:app` depends on `:impl` modules.** That keeps every `impl` replaceable and keeps feature changes from rippling into other features.
- **Features don't reach data sources directly.** `:feature:*` → `:core:data` (or `:core:domain`), never `:core:database` or `:core:network`. See [`android-repository-pattern.md`](./android-repository-pattern.md).
- **`implementation` by default; `api` only when a module's public signatures expose the dependency's types.** `api` leaks the dependency to every consumer and widens recompilation.
- **No cycles.** Gradle rejects them; design so the question never arises.

## The feature `api` / `impl` split

Split a feature when another feature needs to navigate to it or call a small contract of it:

```
:feature:tasks:api     # route types (@Serializable), navigation extension functions, small interfaces
:feature:tasks:impl    # screens, ViewModels, the NavGraphBuilder entry, Hilt modules
```

```kotlin
// :feature:tasks:api
@Serializable data class TaskDetailRoute(val taskId: String)

fun NavController.navigateToTaskDetail(taskId: String, navOptions: NavOptions? = null) =
    navigate(TaskDetailRoute(taskId), navOptions)

// :feature:tasks:impl
fun NavGraphBuilder.tasksGraph(onTaskClick: (String) -> Unit) {
    composable<TasksRoute> { TasksRoute(onTaskClick = onTaskClick) }
    composable<TaskDetailRoute> { TaskDetailRoute() }
}

// :app — the only place that sees every impl and decides who navigates where
NavHost(navController, startDestination = TasksRoute) {
    tasksGraph(onTaskClick = navController::navigateToTaskDetail)
    settingsGraph(onAccountClick = navController::navigateToAccount)
}
```

- **Features expose navigation as lambdas** (`onTaskClick: (String) -> Unit`); `:app` connects them. A feature never holds another feature's screens.
- **Pass IDs, not objects**, across features; the destination loads from the repository.
- Don't split a feature nobody else references. A plain `:feature:settings` is fine until another module needs to reach it.

## Hilt across modules

- **Each module installs its own bindings** in `@Module @InstallIn(SingletonComponent::class)` classes, marked `internal` so the bindings are the only thing exported. `:core:data` binds repository interfaces to their `internal` implementations.
- **`:app` holds `@HiltAndroidApp`** and, by depending on every `impl`, pulls every module into the graph. A module whose bindings never reach `:app`'s classpath silently isn't bound.
- **Test bindings** swap at the same boundary with `@TestInstallIn(components = [...], replaces = [DataModule::class])` in `:core:testing` or the test source set.

## Visibility

- **`internal` by default** for everything that isn't a module's contract: implementations, ViewModels' helpers, mappers, Hilt modules.
- **Enable explicit API mode** (`kotlin { explicitApi() }`) in `:core:*` modules so every public symbol is a deliberate decision. Feature `impl` modules may skip it since only `:app` consumes them.

## Resources across modules

- **Turn on non-transitive R classes** (`android.nonTransitiveRClass=true`, the default since AGP 8). Each module's `R` contains only its own resources, which makes builds faster and stops a feature from reaching another module's strings by accident.
- **A module owns the strings and drawables it uses.** Shared ones live in `:core:designsystem` (icons) or `:core:ui`. Reference them with that module's `R`, imported explicitly.
- **Prefix resources in shared modules** (`resourcePrefix = "core_ui_"` in the module's `android {}`) to avoid merge collisions in the final APK.
- **Each module has its own `namespace`**, matching its package (`com.example.feature.tasks`).

## Build performance

Put these in `gradle.properties` once modules exist; they're what turn modules into speed:

```properties
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.configuration-cache=true
android.nonTransitiveRClass=true
```

- **Keep modules small enough that a typical change touches one or two**; a 400-file "feature" module rebuilds like a monolith.
- **Configuration cost grows with module count.** Convention plugins and configuration cache keep it flat; repeated `android {}` blocks don't. See `android-gradle-architecture-pro`.

## Enforce the graph

Rules nobody checks erode. Check the graph in CI:

- **[module-graph-assertion](https://github.com/jraska/modules-graph-assert)** (`com.jraska.module.graph.assertion`) fails the build on forbidden edges, such as `:feature:*` → `:feature:*:impl` or `:feature:*` → `:core:database`, and on graph height. Verify the configuration syntax against its README for the version you pin.
- **Generate a graph image** (NiA's `graph` task, or `./gradlew :app:dependencies`) for the README, and keep a module table in `CLAUDE.md`, updated with each new module.

## Tests per module

- **Unit tests sit next to the code** in each module's `src/test/`; Compose UI tests for a feature in its `src/androidTest/`. See [`android-testing-strategy.md`](./android-testing-strategy.md).
- **`:core:testing`** holds fakes (`FakeTasksRepository`), `MainDispatcherRule`, and a Hilt test runner, used as `testImplementation(projects.core.testing)`.
- **CI runs affected modules** for pull requests where it can (path filters, or a dependency-aware task selection), and the full suite on `main`.

## Migrating a monolith

Do it incrementally; the app builds and ships after every step.

1. **Add convention plugins first** (`android-gradle-architecture-pro`), so each new module is a few lines.
2. **Extract `:core:model`** (pure data classes), then `:core:common`.
3. **Extract data sources and `:core:data`**, moving Room, Retrofit, and repositories behind interfaces.
4. **Extract `:core:designsystem`** (theme, tokens, icons, components).
5. **Extract one feature at a time**, starting with the leaf that has the fewest inbound references. Move its screens, ViewModels, strings, and tests. Wire its graph from `:app`.
6. **Split a feature into `api`/`impl`** only when another feature needs to reach it.
7. **Stop when `:app` holds only the `Application`, `MainActivity`, the `NavHost`, and the manifest.** New code defaults to a module.

## Common Pitfalls

- **Feature → feature `impl` edges.** The shortcut that rebuilds half the app on every change. Use `api` modules or move the shared piece down.
- **Everything as `api(...)`.** Every consumer recompiles on every change. Default to `implementation`.
- **A "core" module that is the old monolith renamed.** `:core:common` with 300 files has every downside of the monolith. Split by responsibility.
- **Features importing `:core:database` or `:core:network`.** Go through `:core:data`.
- **Strings left in `:app` that features reference through a transitive `R`.** Breaks once non-transitive R is on. Move them to the module that uses them.
- **Public Hilt modules and implementations.** Make them `internal`; export the interface.
- **Over-splitting up front.** Fifty modules for a three-screen app is configuration overhead with no payoff. Let boundaries pull modules apart.
- **No enforcement.** Without a graph check, the first deadline adds a forbidden edge.
