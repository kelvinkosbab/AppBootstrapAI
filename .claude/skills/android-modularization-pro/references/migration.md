# Migrating a single-module app

## What stays in `:app`

| Stays | Why |
|---|---|
| `@HiltAndroidApp` `Application` | Hilt generates the component here and aggregates every module's bindings. |
| `MainActivity` | The launcher entry point; it calls `enableEdgeToEdge()` and sets content to `AppTheme { AppNavHost() }`. |
| `AppNavHost` and top-level destinations | The only place that sees every feature and wires their navigation lambdas. |
| `AndroidManifest.xml` app entries, launcher icons, `res/xml` config (backup rules, network security) | Belong to the installed application. Modules contribute their own manifest entries through merging. |
| App-wide startup (`Timber.plant`, `StrictMode`, WorkManager init) | Runs once per process in `Application.onCreate()`. |

Everything else moves: screens, ViewModels, repositories, DAOs, API services, theme, and strings.

## Prerequisites

1. **Version catalog** for every dependency (see `android-gradle-conventions.md`).
2. **Convention plugins** in `build-logic/convention/` for application, library, Compose, feature, and Hilt (see `android-gradle-architecture-pro`). With them, a new feature's build file is:

   ```kotlin
   plugins {
       alias(libs.plugins.example.android.feature)   // library + Compose + Hilt + common feature deps
   }
   android { namespace = "com.example.feature.tasks.impl" }
   dependencies {
       implementation(projects.feature.tasks.api)
       implementation(projects.core.data)
   }
   ```

3. **Type-safe project accessors** in `settings.gradle.kts`: `enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")`.
4. **Build flags** in `gradle.properties`: `org.gradle.parallel`, `org.gradle.caching`, `org.gradle.configuration-cache`, `android.nonTransitiveRClass` (all `true`). Turn on non-transitive R first and fix the fallout while there's one module; it gets harder later. Android Studio's *Refactor ▸ Migrate to Non-Transitive R Classes* does most of it.
5. **A CI build of `:app` and the unit tests**, so every later step is checked.

## Extraction order

Leaves first, then upward. Each row is a separate, reviewable change:

1. **`:core:model`**: move the data classes. Make it `kotlin("jvm")`; anything that needs Android types stays out.
2. **`:core:common`**: dispatcher qualifiers, coroutine scopes, small extensions.
3. **Data sources**: `:core:database` (Room), `:core:network` (Retrofit), `:core:datastore`. Map their types to `:core:model` at the edge.
4. **`:core:data`**: repository interfaces and `internal` implementations, plus the `@Binds` module (see `android-repository-pattern.md`).
5. **`:core:designsystem`**: theme, tokens, `AppIcons`, components (see `android-design-system-pro`).
6. **`:core:testing`**: fakes and test rules, so moved features keep their tests.
7. **Features, one at a time**, starting with the leaf nothing else navigates to (often settings or about). Move screens, ViewModels, strings, drawables, and tests; add the `NavGraphBuilder` entry; call it from `AppNavHost`.
8. **`api`/`impl` split** for a feature as soon as another feature needs to reach it.

## Per-step checklist

- [ ] Create the module directory and `build.gradle.kts` (convention plugin, `namespace`, dependencies).
- [ ] Add `include(":…")` to `settings.gradle.kts`.
- [ ] Move files with `git mv` to keep history, and update the `package` lines to match the new `namespace`.
- [ ] Move the strings and drawables the files use into the module's `res/`. Update `R` imports to the module's own `R`.
- [ ] Make the module's contract public and everything else `internal`. Hilt modules and implementations are `internal`.
- [ ] Add `implementation(projects.…)` where the module is now needed; remove now-unused dependencies from `:app`.
- [ ] Move the matching tests into the module's `src/test/` and `src/androidTest/`.
- [ ] Verify: `./gradlew :<module>:check`, `./gradlew :app:assembleDebug`, and launch the app to the moved screens.
- [ ] Update the module table in `CLAUDE.md` and the graph check's rules if needed.

## Common breakages while moving

- **`Unresolved reference: R` or wrong resources**: the code used `:app`'s `R` transitively. Import the module's own `R`, and move or duplicate the resource into the module that uses it.
- **Resource merge conflicts** (two modules define `ic_close`): add `resourcePrefix` to shared modules and rename.
- **Hilt "cannot be provided without an @Provides"**: the binding's module isn't on `:app`'s classpath, or the binding class became `private`. Add the dependency to `:app`; keep bindings `internal`, not `private`.
- **`Cannot access 'X': it is internal in 'module'`**: either X is part of the contract (make it public) or the caller is in the wrong module.
- **Manifest merge errors**: a module declares an `<activity>` or permission that conflicts with `:app`. Keep component declarations in the module that owns the class; use `tools:node` rules only with a comment.
- **Kapt/KSP processors not running in the new module**: the convention plugin didn't apply KSP there. Apply the Hilt or Room convention plugin.
- **Previews break**: preview data lived in `:app`. Move preview fixtures into the module or `:core:testing`.

## Splitting an oversized module

1. List its packages by sub-area and who uses each (the dependency script in `references/audit.md`, or Android Studio's *Analyze ▸ Analyze Module Dependencies*).
2. Pick the sub-area with the fewest inbound references.
3. Create the new module, move the sub-area, and make the old module depend on the new one, never the reverse.
4. Repoint consumers that only needed the new module.

## Finishing

The migration is done when:

- `:app` contains only what the table above lists;
- every module has its own unit tests, and fakes come from `:core:testing`;
- the graph check runs in CI and passes;
- `CLAUDE.md` lists every module, its purpose, and the graph.
