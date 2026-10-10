---
name: android-modularization-pro
description: Plans, audits, and migrates Android apps to a multi-module Gradle build (the Now in Android layout) — a thin :app over feature (api/impl), data, domain, model, and core modules, with cross-feature navigation through :app, Hilt bindings per module, non-transitive resources, and an enforced dependency graph. Use when modularizing a single-module app, designing a new app's module graph, splitting an oversized module, or reviewing whether a multi-module project's graph is healthy.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "Now in Android (https://github.com/android/nowinandroid), Android Developers 'Guide to Android app modularization', Gradle build-performance docs, the android-modular-architecture rule"
---

Turn an Android app into a thin `:app` over many small Gradle modules, or check one that already is. This is the deep companion to the always-on `android-modular-architecture.md` rule. The rule steers while writing; this skill plans a graph, audits a whole build, and drives a migration one module at a time.

Pick the mode from the request:

- **Plan**: a new app, or a single-module app before any move. Produce a module map (module · type · purpose · dependencies) and the extraction order, using `references/module-graph.md`. Start small (`:core:model`, `:core:data`, `:core:designsystem`, one feature) and say which later splits you'd expect.
- **Migrate**: move code out of `:app`, or out of an oversized module, following `references/migration.md`. One module per step, the app building and tests passing after each.
- **Audit**: an app that already has modules. Run the checks in `references/audit.md`, then report findings ranked by severity.

Review process (audit mode):

1. Inventory: `settings.gradle.kts` includes, each module's plugins and Kotlin file count, `:app`'s Kotlin files, and `gradle.properties` build flags. Use `references/audit.md` ("Inventory").
2. Check the graph with `references/module-graph.md` and the dependency report in `references/audit.md`: feature→feature `impl` edges, features reaching data sources, `api(...)` overuse, `:impl` modules consumed outside `:app`, oversized or near-empty modules.
3. Check navigation and DI with `references/navigation-and-di.md`: how features reach each other, where the `NavHost` lives, Hilt module visibility, test bindings.
4. Check resources, visibility, and build flags: non-transitive R, resource prefixes, `internal`/explicit API, configuration cache and build cache.
5. Check enforcement: is there a module-graph assertion in CI, and a module table in `CLAUDE.md`?

If doing a partial review, load only the relevant reference file.

## Core Instructions

- **`:app` is an assembler.** It keeps the `Application`, `MainActivity`, the top-level `NavHost`, the manifest, and launcher resources. Screens, ViewModels, and repositories belong in modules.
- **Direction is the architecture.** `:app` → features → domain → data → data sources → model. Features never depend on another feature's `impl`; shared needs move down into `:core:*`.
- **Navigation goes through `:app`.** Features expose a `NavGraphBuilder` entry and navigation lambdas; the `api` module holds routes. `:app` connects them.
- **Incremental, never big-bang.** Every step leaves the app building and shippable. Convention plugins come first so each new module costs a few lines.
- **`implementation` and `internal` by default.** `api(...)` and public symbols are deliberate, reviewed choices.
- **Granularity follows real boundaries.** Split for a second owner, a heavy dependency only part of the code needs, reuse by another app (Wear, TV), or slow builds. Don't split speculatively.
- **Enforce what you decide.** A graph rule without a CI check is a suggestion.
- **Severity by cost**: broken (a missing Hilt binding at runtime because a module never reaches `:app`, resources resolving through a transitive `R` that breaks when non-transitive R is on, a dynamic feature with a missing split) > boundary leak (feature→feature `impl` edge, features importing `:core:database` or `:core:network`, logic in `:app`, `api` leaks) > shape (oversized or near-empty modules, missing graph check or module table).
- Cross-reference, don't duplicate: convention plugins, catalogs, and AGP versions go to `android-gradle-architecture-pro`; ViewModel and UiState shape to `android-mvvm-architecture.md`; repositories to `android-repository-pattern.md`; design-system contents to `android-design-system-pro`; Compose performance to `android-compose-pro`.

## Output Format

**Plan mode:** a module table (module · type · purpose · depends on), a Mermaid or indented-text graph, the extraction order with one line per step, and what `:app` will contain at the end.

**Migrate mode:** for each step, the files moved, the new module's `build.gradle.kts` (convention plugins plus dependencies), the `settings.gradle.kts` include, symbols made public or `internal`, and the commands run to verify it (`./gradlew :module:check`, `./gradlew :app:assembleDebug`).

**Audit mode:** findings grouped by module (or "Build"). Each finding gives the file and line, the violated principle, why it costs something (build time, testability, a runtime break), and a brief before/after. Skip clean modules. End with an inventory table and a prioritized plan.

Example finding:

### feature/settings/build.gradle.kts

**Line 14: `:feature:settings` depends on `:feature:account` to open the account screen. Every change inside Account now recompiles Settings, and Settings can't be tested without Account's whole dependency tree.**

```kotlin
// Before
dependencies {
    implementation(projects.feature.account)
}

// After: Settings only knows a lambda; :app connects it to Account's route
dependencies {
    // no feature dependency
}

// :feature:settings:impl
fun NavGraphBuilder.settingsGraph(onAccountClick: () -> Unit) { /* ... */ }

// :app
settingsGraph(onAccountClick = navController::navigateToAccount)  // from :feature:account:api
```

### Summary

| Inventory | Count |
|---|---|
| Modules | 11 |
| Kotlin files in `:app` (excluding `Application` / `MainActivity`) | 23 |
| Feature→feature `impl` edges | 2 |
| Features depending on `:core:database` / `:core:network` | 1 |
| `api(...)` declarations | 9 |
| Graph check in CI | none |

1. **Broken:** `:feature:tasks` reads `R.string.app_name` from `:app` through the transitive `R`; it fails once `android.nonTransitiveRClass=true`. Move the string to the module.
2. **Boundary leak:** 23 files in `:app`, including `TaskListViewModel`. Move them to `:feature:tasks:impl` with their tests.
3. **Boundary leak:** the Settings → Account and Tasks → Settings edges.
4. **Shape:** add a module-graph assertion and a module table in `CLAUDE.md`.

End of example.

## References

- `references/module-graph.md` — module types and what each holds, allowed edges, the `api`/`impl` split, naming, granularity heuristics, extra targets (Wear, widgets, dynamic features), a worked example graph.
- `references/migration.md` — what stays in `:app`, prerequisites, extraction order, per-step checklist, resources and non-transitive R, Hilt and manifest merging, common breakages.
- `references/navigation-and-di.md` — type-safe routes in `api` modules, `NavGraphBuilder` entries, lambdas wired in `:app`, Hilt bindings per module, `internal` modules, test replacement with `@TestInstallIn`.
- `references/audit.md` — inventory commands, a dependency-rule script over `build.gradle.kts` files, searches, the module-graph-assertion setup, and the CI job.
