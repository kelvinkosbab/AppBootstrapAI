# Android Gradle File Inventory

A non-trivial Android project has a specific set of build files, each with a defined responsibility. Mixing concerns across these files (e.g., declaring repositories in a module's `build.gradle.kts` instead of `settings.gradle.kts`) creates drift and merge conflicts.

## `settings.gradle.kts` (project root)

Single file. Owns:

- **`pluginManagement {}`** — where Gradle looks for build-script plugins. Always include `google()`, `mavenCentral()`, `gradlePluginPortal()`.
- **`dependencyResolutionManagement {}`** — where Gradle looks for *runtime* dependencies. Set `repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS` so individual modules can't re-declare repositories (forces centralization).
- **`rootProject.name`** — the project name.
- **`include(":module-a", ":module-b", ...)`** — every module in the build, listed here.
- **`includeBuild("build-logic")`** — composite-build inclusion of the convention-plugin module (see `convention-plugins.md`).

Don't put dependency declarations or `android {}` blocks here.

## Root `build.gradle.kts` (project root)

Single file. Should be **minimal**:

```kotlin
// Top-level build file where you can add configuration options common to all
// sub-projects/modules.
plugins {
    // Declare plugin coordinates but don't apply them — modules apply.
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.hilt) apply false
    alias(libs.plugins.ksp) apply false
}
```

- **`apply false`** declares the plugin's classpath without applying it. Individual modules then `alias(...)` (no `apply false`) to actually use it.
- **No `allprojects {}` or `subprojects {}`** for new code — those run during configuration and slow down builds. Use convention plugins instead (see `convention-plugins.md`).
- **No dependency declarations** — modules declare their own.

## Module `build.gradle.kts` (per module)

One per module — `app/build.gradle.kts`, `feature/home/build.gradle.kts`, etc.

Three sections:

```kotlin
plugins {
    // Apply the convention plugin AND any module-specific plugins.
    alias(libs.plugins.kozinga.android.feature)        // convention
    alias(libs.plugins.kozinga.android.library.compose) // convention
}

android {
    // Module-specific config ONLY — namespace, optional buildTypes overrides.
    namespace = "com.kozinga.feature.home"
}

dependencies {
    // Module-specific deps.
    implementation(project(":core:ui"))
    implementation(project(":data:repositories"))
    implementation(libs.androidx.lifecycle.runtime.compose)
}
```

- **Repeated `android { compileSdk = ...; defaultConfig { minSdk = ... } }`** in every module is the #1 smell — that's what convention plugins exist to factor.
- **No inline dependency strings** — every dependency goes through `libs` (the version catalog accessor).
- **No `repositories {}` block** — `dependencyResolutionManagement` in `settings.gradle.kts` owns this.

## `gradle/libs.versions.toml`

Single file at `gradle/libs.versions.toml`. Gradle auto-discovers it as `libs`.

Four sections:

- `[versions]` — every version literal, keyed.
- `[libraries]` — every dependency artifact, referencing `[versions]`.
- `[plugins]` — every Gradle plugin, with id + version reference.
- `[bundles]` — optional groups of libraries that ship together.

See `version-catalogs.md` for depth.

## `gradle.properties`

Project-wide Gradle flags:

```properties
# Performance
org.gradle.jvmargs=-Xmx4096m -XX:+UseG1GC
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.configuration-cache=true

# Android
android.useAndroidX=true
android.nonTransitiveRClass=true

# Kotlin
kotlin.code.style=official
```

- **Enable `configuration-cache=true`** for build-speed gains on incremental builds. NiA enables it.
- **`nonTransitiveRClass=true`** is the default in AGP 8.x; explicit is fine.

## `build-logic/` (composite build)

A separate Gradle build (not a regular module) included via `includeBuild("build-logic")` in `settings.gradle.kts`. Houses convention plugins. See `convention-plugins.md`.

Layout:

```
build-logic/
├── settings.gradle.kts          # its own settings, refers to libs.versions.toml from parent
├── convention/
│   ├── build.gradle.kts
│   └── src/main/kotlin/
│       ├── AndroidApplicationConventionPlugin.kt
│       ├── AndroidLibraryConventionPlugin.kt
│       ├── AndroidFeatureConventionPlugin.kt
│       ├── AndroidLibraryComposeConventionPlugin.kt
│       └── AndroidHiltConventionPlugin.kt
└── README.md                    # describe what each plugin sets up
```

## `gradle/wrapper/`

Two files:

- `gradle-wrapper.jar` — committed.
- `gradle-wrapper.properties` — committed. Pins Gradle version (`distributionUrl=...gradle-8.10-bin.zip`).

Update via `./gradlew wrapper --gradle-version <new>`. Both files change together — review as a unit.

## What's NOT in the build files

- **`local.properties`** — gitignored. Contains `sdk.dir` and other machine-specific paths.
- **`gradle.lockfile`** — opt-in (see `android-gradle-conventions.md`).
- **`buildSrc/`** — superseded by `build-logic/`. Don't add a new `buildSrc/` to a new project.

## Inventory checklist for review

When you open a project:

1. **`settings.gradle.kts` exists and includes `pluginManagement` + `dependencyResolutionManagement` + every module + `includeBuild("build-logic")`** (if multi-module). ✓
2. **Root `build.gradle.kts` is minimal** — only plugin declarations with `apply false`. ✓
3. **Each module `build.gradle.kts` is ~30 lines or less** — convention plugin applied at top, namespace declared, dependencies listed. ✓
4. **`libs.versions.toml` exists** and is the only place version literals appear. ✓
5. **`build-logic/convention/`** exists with at least one convention plugin per common module shape (app, library, feature, compose, hilt). ✓
6. **`gradle.properties`** has parallel + caching enabled. ✓

A "no" answer to any of these is a finding. The priority depends on how many modules the project has — single-module apps get a pass on convention plugins; 5+ module apps don't.
