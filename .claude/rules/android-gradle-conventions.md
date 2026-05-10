---
description: Conventions for authoring Android Gradle build files — Kotlin DSL, version catalogs, AGP/Kotlin/Compose-compiler co-versioning, multi-module graph patterns, library publishing
globs: "**/*.gradle.kts,**/settings.gradle.kts,**/libs.versions.toml,**/gradle/libs.versions.toml"
---

# Android Gradle Conventions

Authoring strategy for Android build scripts and version catalogs. Covers Kotlin DSL discipline, single-source-of-truth version management, multi-module graph patterns, and library publishing.

## Kotlin DSL Only

- **Use `.gradle.kts`**, never legacy `.gradle` (Groovy). All build scripts: `build.gradle.kts`, `settings.gradle.kts`, `init.gradle.kts`.
- **Plugins applied via the `plugins {}` block:**

  ```kotlin
  plugins {
      alias(libs.plugins.android.application)
      alias(libs.plugins.kotlin.android)
      alias(libs.plugins.kotlin.compose)   // Compose Compiler plugin (Kotlin 2.0+)
      alias(libs.plugins.hilt)
      alias(libs.plugins.ksp)
  }
  ```

- **Never `apply plugin: "..."`** at the top — that's legacy Groovy syntax that compiles but bypasses Gradle's plugin DSL improvements (version pinning, catalog integration).
- **No `buildscript {}` block at the module level.** Plugin versions belong in `libs.versions.toml` and the root project's `pluginManagement` block.

## Version Catalogs (`libs.versions.toml`)

Single source of truth for every version, dependency, and plugin. Lives at `gradle/libs.versions.toml`.

```toml
[versions]
agp = "8.7.0"
kotlin = "2.0.21"
compose-compiler = "1.5.15"  # Pre-Kotlin 2.0; otherwise the kotlin-compose plugin handles this
hilt = "2.52"
ksp = "2.0.21-1.0.28"
coroutines = "1.9.0"
lifecycle = "2.8.7"

[libraries]
androidx-core-ktx       = { group = "androidx.core",       name = "core-ktx",       version = "1.15.0" }
androidx-lifecycle-vm   = { group = "androidx.lifecycle",  name = "lifecycle-viewmodel-compose", version.ref = "lifecycle" }
androidx-lifecycle-rt   = { group = "androidx.lifecycle",  name = "lifecycle-runtime-compose",   version.ref = "lifecycle" }
hilt-android            = { group = "com.google.dagger",   name = "hilt-android",                version.ref = "hilt" }
hilt-compiler           = { group = "com.google.dagger",   name = "hilt-android-compiler",       version.ref = "hilt" }
kotlinx-coroutines      = { group = "org.jetbrains.kotlinx", name = "kotlinx-coroutines-android", version.ref = "coroutines" }

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
android-library     = { id = "com.android.library",     version.ref = "agp" }
kotlin-android      = { id = "org.jetbrains.kotlin.android",  version.ref = "kotlin" }
kotlin-compose      = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
hilt                = { id = "com.google.dagger.hilt.android",     version.ref = "hilt" }
ksp                 = { id = "com.google.devtools.ksp",            version.ref = "ksp" }

[bundles]
lifecycle = ["androidx-lifecycle-vm", "androidx-lifecycle-rt"]
```

- **One catalog file** at `gradle/libs.versions.toml` — Gradle picks it up automatically as `libs`.
- **Group versions in `[versions]`** so a coordinated bump (Kotlin and KSP move together) is one edit.
- **Use `version.ref = "key"` for shared versions**; literal `version = "..."` only when truly unique.
- **`[bundles]`** for groups of libraries always declared together (`implementation(libs.bundles.lifecycle)`).
- **Hyphens in catalog keys** become dots in code: `androidx-core-ktx` → `libs.androidx.core.ktx`.

## AGP / Kotlin / Compose-Compiler Co-Versioning

These three move in lockstep — mismatched versions produce confusing errors.

- **Kotlin 2.0+** — use the `org.jetbrains.kotlin.plugin.compose` plugin instead of manually setting `composeOptions.kotlinCompilerExtensionVersion`. The plugin tracks the Kotlin version automatically.
- **Pre-Kotlin 2.0** — `composeOptions { kotlinCompilerExtensionVersion = libs.versions.compose.compiler.get() }` and pin the Compose Compiler version in the catalog. Check the [Compose-to-Kotlin compatibility matrix](https://developer.android.com/jetpack/androidx/releases/compose-kotlin) for the right pairing.
- **AGP versions track Android Studio releases** — pin to the AGP that matches your team's Android Studio install, not bleeding-edge.

## `compileSdk` / `targetSdk` / `minSdk`

```kotlin
android {
    namespace = "com.kozinga.myapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.kozinga.myapp"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }
}
```

- **`compileSdk`** = newest API you've tested against; bump on each yearly release after dogfooding.
- **`targetSdk`** = the API your app explicitly supports. Bumping this opts into runtime behavior changes (background restrictions, scoped storage, etc.). Test before bumping.
- **`minSdk`** = lowest device version you support. Lower = wider audience, more API guards. Pick deliberately.
- **`namespace`** is the package for `R.*` and `BuildConfig`. Distinct from `applicationId` (which is the install identifier).

## `jvmToolchain`

```kotlin
kotlin {
    jvmToolchain(17)
}
```

- **Use `jvmToolchain(N)`** — Gradle downloads the JDK if needed and uses it consistently for compilation, tests, and KSP. Replaces both `compileOptions.sourceCompatibility/targetCompatibility` and `kotlinOptions.jvmTarget`.
- **Don't mix `jvmToolchain` with explicit `compileOptions`** — they fight each other. Pick one (toolchain) and remove the other.
- **JDK 17 is the current Android baseline** for AGP 8+. JDK 21 works for newer AGP versions; check release notes.

## `api` vs `implementation`

```kotlin
dependencies {
    api(libs.androidx.lifecycle.vm)        // Re-exported to consumers — they can use it without a direct dep
    implementation(libs.kotlinx.coroutines)  // Used internally only — invisible to consumers
    ksp(libs.hilt.compiler)                  // Compile-time annotation processor (KSP)
}
```

- **`implementation` is the default.** Internal-only — bumping it is a non-breaking change.
- **`api` only when consumers reference the library's types in *your* public API signatures.** Bumping an `api` dependency is potentially breaking (consumers see the type change).
- **`compileOnly`** for libraries needed at compile time but not at runtime (annotation libraries with `@Retention(SOURCE)`, e.g.).
- **`ksp` (`kapt` is legacy)** for annotation processors. Hilt, Room, Moshi codegen all run on KSP now — use it. `kapt` is slower and on a deprecation path.

## Multi-Module Graph

Standard pattern for non-trivial apps:

```
:app                       ← thin entry point, DI graph wiring, manifest, MainActivity
:feature:home              ← screen-feature modules (one per major feature)
:feature:settings
:feature:profile
:data:repositories         ← repos sit between feature modules and the network/persistence
:data:network              ← Retrofit setup, API interfaces
:data:persistence          ← Room database, DAOs
:core:ui                   ← shared Composables, themes, design system
:core:common               ← logging, dispatcher qualifiers, base classes
:core:testing              ← shared test fakes, MainDispatcherRule, fixtures
```

- **`:app` depends on every `:feature:*`**, never the other way around. Features depend on `:data:*` and `:core:*`.
- **`:feature:*` modules don't depend on each other.** Cross-feature navigation routes through `:app` or a dedicated navigation graph.
- **`:core:testing`** with the `androidTest` test-fixtures plugin (`testFixtures` source set) — share the `MainDispatcherRule`, `MockData`, etc. across module test suites.
- **`include(":app", ":feature:home", ...)`** in `settings.gradle.kts` — list every module here.

## Library Modules (`com.android.library`)

```kotlin
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "com.kozinga.coreui"
    compileSdk = 34

    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")  // ProGuard rules consumers inherit
    }
}
```

- **`consumer-rules.pro`** — ProGuard/R8 keep rules that *consumers* of this library inherit. Use for libraries that ship public reflection-using types (Moshi adapters, Room schemas) that consumers' R8 must not strip.
- **`proguardFiles(...)` (without `consumer`)** applies only to the library's own minified release builds, not consumers'. For an `application`, use this; for a `library` shipping rules to consumers, use `consumer`.
- **Library modules don't have `applicationId`** — that's an `application`-only field.
- **`minSdk` on a library** means consumers' `minSdk` must be ≥ this value. Aim for the lowest reasonable.

## Maven Publishing (for libraries published to a repo)

```kotlin
plugins {
    alias(libs.plugins.android.library)
    `maven-publish`
}

afterEvaluate {
    publishing {
        publications {
            register<MavenPublication>("release") {
                from(components["release"])
                groupId    = "com.kozinga"
                artifactId = "core-ui"
                version    = "1.0.0"
            }
        }
    }
}
```

- **`afterEvaluate { ... }`** is required because the `release` software component is registered late in the AGP lifecycle.
- **Version stays in the `[versions]` table** of the catalog; don't hard-code in `build.gradle.kts`.
- **For internal team Maven repos**, prefer `vanniktech/gradle-maven-publish-plugin` — much less ceremony than raw `maven-publish`.

## Where Configuration Lives

- **Root `build.gradle.kts`** — plugin declarations (top-level), repository configuration if not in `settings.gradle.kts`, and *only* truly project-wide config (e.g., a `subprojects { ... }` block applying ktlint to every module).
- **Root `settings.gradle.kts`** — `pluginManagement {}`, `dependencyResolutionManagement { repositories { ... } }`, the `include(...)` list of modules, and the version-catalog reference.
- **Module-level `build.gradle.kts`** — that module's plugins, dependencies, `android {}` block, and module-specific settings only. *Don't* repeat catalog declarations or repositories.
- **JaCoCo / Sonar / convention plugins** — root `build.gradle.kts` or a `buildSrc/` / `build-logic/` convention plugin module so config doesn't drift across feature modules.

## Common Pitfalls

- **Mixing Groovy and Kotlin DSL** — `build.gradle` and `build.gradle.kts` in the same project. Pick one (Kotlin); migrate the other.
- **Hard-coded versions in `build.gradle.kts`** instead of the catalog — works, but each version exists in N places now and bumps drift.
- **Missing `version.ref` on dependencies** that should track a shared version — bumping `lifecycle` in one place but not its sibling artifacts.
- **`composeOptions.kotlinCompilerExtensionVersion` set under Kotlin 2.0+** — the new Compose plugin manages this; setting it manually causes mismatches.
- **`compileOnly` instead of `implementation`** for libraries used at runtime — runs fine in dev, NoClassDefFoundError in release.
- **`api` overuse** — every library starts as `api` because it works, then every change is breaking.
- **`kapt` for annotation processors that support KSP** — slow and a known deprecation path.
- **`buildscript {}` in module `build.gradle.kts`** — legacy Groovy pattern; modern Kotlin DSL puts plugins in `pluginManagement` (settings) and `plugins {}` (modules).
- **No `consumer-rules.pro` on libraries that ship reflection-dependent code** — consumer apps with R8 enabled crash at runtime when classes get stripped.
- **`include(":app")` listed but module folder missing or vice versa** — silent failures or confusing errors. Cross-check `settings.gradle.kts` against the on-disk module list.
- **`namespace` and `applicationId` confused** — they can match, but `applicationId` is the install identifier (changes break upgrades) and `namespace` is the `R.*` package. Treat as separate concepts.
- **Plugins applied via legacy `apply plugin: "..."`** — works, but bypasses version-catalog wiring and DSL features.

## Patterns to Follow

```kotlin
// settings.gradle.kts
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "MyApp"

include(":app")
include(":feature:home", ":feature:settings")
include(":data:repositories", ":data:network", ":data:persistence")
include(":core:ui", ":core:common", ":core:testing")
```

```kotlin
// app/build.gradle.kts
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.kozinga.myapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.kozinga.myapp"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "com.kozinga.myapp.HiltTestRunner"
    }

    buildFeatures { compose = true }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(project(":feature:home"))
    implementation(project(":feature:settings"))
    implementation(project(":data:repositories"))
    implementation(project(":core:ui"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
}
```

```kotlin
// core/ui/build.gradle.kts (library module)
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.kozinga.core.ui"
    compileSdk = 34

    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")
    }

    buildFeatures { compose = true }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    api(libs.androidx.lifecycle.rt)   // Re-exported because public Composables expose it
    implementation(libs.androidx.core.ktx)
}
```
