# Module graph

## Layers and allowed edges

```
:app                         Application, MainActivity, NavHost, manifest
  └─ :feature:*:impl         screens, ViewModels, the feature's NavGraphBuilder entry
       ├─ :feature:*:api     routes and small contracts other features may use
       └─ :core:ui           composables that take domain models
            │
            ▼  everything above may depend on everything below
:core:domain (optional) → :core:data → :core:database · :core:network · :core:datastore
:core:designsystem          Compose + M3 only
            │
            ▼
:core:model · :core:common  pure Kotlin; no Android UI
```

| From → To | Allowed? |
|---|---|
| `:app` → anything | ✅ it is the assembler |
| `:feature:x:impl` → `:feature:y:api` | ✅ routes and small contracts only |
| `:feature:x:impl` → `:feature:y:impl` | ❌ move the shared piece down, or add an `api` |
| `:feature:*` → `:core:data`, `:core:domain`, `:core:ui`, `:core:designsystem`, `:core:model` | ✅ |
| `:feature:*` → `:core:database`, `:core:network`, `:core:datastore` | ❌ go through `:core:data` |
| `:core:*` → `:feature:*` | ❌ |
| `:core:designsystem` → `:core:model`, `:core:data` | ❌ components take primitives and lambdas (`:core:ui` is the place for model-aware composables) |
| `:core:model` → anything Android | ❌ keep it `kotlin("jvm")` |
| anything other than `:app` → `:feature:*:impl` | ❌ |
| `:core:testing` → the modules it fakes | ✅ used only as `testImplementation` / `androidTestImplementation` |

## Module types

- **`:app`**: `@HiltAndroidApp` `Application`, `MainActivity` (`enableEdgeToEdge()`, `setContent { AppTheme { AppNavHost() } }`), the `NavHost` that calls every feature's graph entry, the manifest, launcher icons, and app-level config (`BuildConfig` flags, `StrictMode`).
- **Feature**: one per user-facing area. Holds screens (`…Route` + `…Screen`), ViewModels, feature-only strings and drawables, and its graph entry. Split into `api`/`impl` only when another module needs to navigate to it or use a contract.
- **`:core:data`**: repository interfaces and `internal` implementations plus their Hilt `@Binds` module. The only door to data for features.
- **`:core:domain`** (optional): use cases reused by several features or combining repositories. Skip it when it would only forward calls.
- **Data sources**: `:core:database` (Room entities, DAOs), `:core:network` (Retrofit services, DTOs), `:core:datastore` (preferences, proto DataStore). Their types never leave `:core:data`.
- **`:core:model`**: plain `data class`es and value-class IDs shared by every layer. Pure Kotlin, so it compiles fast and can be shared with KMP later.
- **`:core:designsystem`** and **`:core:ui`**: tokens and primitive components, then the composables that know domain models (see `android-design-system.md`).
- **`:core:common`**: dispatcher qualifiers, `@ApplicationScope`, result helpers, Timber setup. Keep it small; it is the module most likely to rot into a junk drawer.
- **`:core:testing`**: fakes, `MainDispatcherRule`, Hilt test runner, test data factories.
- **`:sync`** (optional): WorkManager workers that keep data fresh, depending on `:core:data`.

## Naming

- Use nested paths: `:feature:tasks:impl`, `:core:data`. Enable type-safe project accessors (`enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")`) so dependencies read `projects.feature.tasks.api`.
- Use the same module names as the iOS app where one exists (`FeatureTasks` ↔ `:feature:tasks`), per `cross-platform-development.md`.
- Each module's `namespace` matches its package: `com.example.feature.tasks.impl`.

## Granularity heuristics

Split when:

- a module has **two reasons to change** owned by different people or features;
- part of it pulls a **heavy dependency** (a vendor SDK, ML Kit, maps) the rest doesn't need;
- **another app or target** (Wear OS, TV, a widget, a dynamic feature) needs part of it;
- its incremental build is slow enough to notice, typically past a couple of hundred Kotlin files.

Don't split when:

- the new module would have a single consumer and no tests of its own;
- it would hold only an interface (put it in the module that owns the concept);
- splitting forces `public` on internal implementation details.

Now in Android has around 30 modules for a mid-sized app. A three-screen app needs closer to six.

## Extra targets

- **Wear OS, TV, Automotive** apps are separate `com.android.application` modules that depend on the same `:core:*` modules and their own form-factor features. They never depend on the phone app's `:app`.
- **Widgets (Glance)** live in a feature-like module that depends on `:core:data` and `:core:designsystem`.
- **Dynamic feature modules** (`com.android.dynamic-feature`) invert one edge: the dynamic feature depends on `:app`, and `:app` lists it in `dynamicFeatures`. Reach them by class name or a small `api` interface loaded through the split install, never by a compile-time dependency from `:app`.

## Worked example: a task app

| Module | Type | Purpose | Depends on |
|---|---|---|---|
| `:core:model` | model | `Task`, `TaskId` | — |
| `:core:common` | common | dispatcher qualifiers, `@ApplicationScope` | — |
| `:core:database` | data source | Room `TaskEntity`, `TaskDao` | model |
| `:core:network` | data source | Retrofit `TasksApi`, `NetworkTask` | model, common |
| `:core:data` | data | `TasksRepository`, `OfflineFirstTasksRepository`, `DataModule` | database, network, model, common |
| `:core:designsystem` | design system | `AppTheme`, `AppIcons`, components | — |
| `:core:ui` | shared UI | `TaskRow` | designsystem, model |
| `:core:testing` | testing | `FakeTasksRepository`, `MainDispatcherRule` | data, model |
| `:feature:tasks:api` | feature api | `TasksRoute`, `TaskDetailRoute`, `navigateToTaskDetail` | — |
| `:feature:tasks:impl` | feature impl | list + detail screens, ViewModels, `tasksGraph()` | tasks:api, data, ui, designsystem |
| `:feature:settings` | feature | settings screens, `settingsGraph()` | data, designsystem |
| `:app` | app | `TasksApplication`, `MainActivity`, `AppNavHost` | every feature, designsystem |

`:feature:settings` has no `api`/`impl` split because nothing navigates into it except `:app`.
