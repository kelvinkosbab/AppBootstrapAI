---
description: Structure Android apps as a thin :app module over many small Gradle modules (feature, data, domain, model, core) — why it wins, module types and allowed edges, cross-feature navigation, Hilt and resources across modules, enforcing the graph, and migrating a monolith incrementally
globs: "**/settings.gradle.kts,**/build.gradle.kts,**/*.kt"
paths:
  - "**/settings.gradle.kts"
  - "**/build.gradle.kts"
  - "**/*.kt"
must:
  - "Keep `:app` thin over `:feature:*` and `:core:*` modules; the graph flows one way."
  - "Features never depend on another feature's implementation; only `:app` sees `impl` modules and owns the `NavHost`."
  - "Keep Hilt bindings `internal` per module; enable non-transitive R classes."
---

# Android Modular Architecture

A thin `:app` over many small Gradle modules, as Now in Android does. This is the checklist; the full rule with the module catalog, navigation code, migration steps, and the reasons is in [`architecture-conventions.md`](../skills/android-modularization-pro/references/architecture-conventions.md). `android-modularization-pro` plans, migrates, and audits; build mechanics stay with `android-gradle-architecture-pro`.

## Module types

- **`:app`** holds `@HiltAndroidApp`, the `NavHost`, and the wiring, and depends on every `impl`.
- **`:feature:*`**, split into `:api` (routes, small contracts) and `:impl` when another feature navigates in.
- **`:core:data`** (repositories), optional **`:core:domain`** (use cases), data sources (`:core:database`, `:core:network`, `:core:datastore`), **`:core:designsystem`**, **`:core:ui`**, **`:core:testing`**.
- **`:core:model` is pure Kotlin** (`kotlin("jvm")`).
- **Start with what you need** and split when real boundaries appear; fifty modules for three screens is overhead.

## Dependency rules

- **One direction:** `:app` → features → `:core:domain` → `:core:data` → data sources → `:core:model`. No cycles.
- **Features never depend on another feature's `impl`**, only on its `:api`; shared code moves down into `:core:*`. Only `:app` sees `impl` modules.
- **Features never reach data sources directly**; they go through `:core:data` (see [`android-repository-pattern.md`](./android-repository-pattern.md)).
- **`implementation` by default; `api` only** when public signatures expose the dependency's types.
- **Navigation crosses features as lambdas**, carrying IDs, not objects; `:app` connects them.
- **No renamed monolith**: a 300-file `:core:common` is still a monolith. Split by responsibility.

## Hilt, visibility, resources

- **Each module installs its own `internal` Hilt module**, binding interfaces to `internal` implementations; tests replace them with `@TestInstallIn`.
- **`internal` by default**; `explicitApi()` in `:core:*`.
- **Non-transitive R** (`android.nonTransitiveRClass=true`): each module owns its strings and drawables, shared ones live in `:core:designsystem` / `:core:ui` with a `resourcePrefix`, and each module has its own `namespace`.

## Build, tests, enforcement

- **Parallel builds, build cache, configuration cache on**; convention plugins instead of repeated `android {}` blocks.
- **Tests sit in each module**; fakes and `MainDispatcherRule` in `:core:testing`. CI runs affected modules on PRs and everything on `main`.
- **Enforce the graph in CI** (`com.jraska.module.graph.assertion` for forbidden edges) and keep a module table in `CLAUDE.md`.
- **Migrate leaf-first**, one module per change.
