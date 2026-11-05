---
description: Conventions for authoring Android Gradle build files — Kotlin DSL, version catalogs, AGP/Kotlin/Compose-compiler co-versioning, multi-module graph patterns, library publishing
globs: "**/*.gradle.kts,**/settings.gradle.kts,**/libs.versions.toml,**/gradle/libs.versions.toml"
paths:
  - "**/*.gradle.kts"
  - "**/settings.gradle.kts"
  - "**/libs.versions.toml"
  - "**/gradle/libs.versions.toml"
must:
  - "Kotlin DSL only, with plugins via `alias(libs.plugins.…)`; never `apply plugin:` or module-level `buildscript {}`."
  - "Every version, library, and plugin lives in `gradle/libs.versions.toml`; no inline coordinates."
  - "Use KSP, not kapt; `implementation` by default, `api` only for types in your public signatures."
  - "Never commit `local.properties` or `build/`; commit the Gradle wrapper."
---

# Android Gradle Conventions

The must-follow rules for build scripts and version catalogs. Examples, migration steps, and edge cases live in [`android-gradle-architecture-pro/references/build-script-conventions.md`](../skills/android-gradle-architecture-pro/references/build-script-conventions.md); read the matching section only when a line below isn't enough. Module boundaries are in [`android-modular-architecture.md`](./android-modular-architecture.md).

## Build scripts

- **Kotlin DSL only** (`.gradle.kts`). Plugins via `plugins { alias(libs.plugins.…) }`; never `apply plugin:` or a module-level `buildscript {}`.
- **`settings.gradle.kts` owns** `pluginManagement`, `dependencyResolutionManagement` (`FAIL_ON_PROJECT_REPOS`), and the `include(...)` list, which must match the modules on disk.
- **Repeated `android {}` config moves into `build-logic/` convention plugins** once two modules share it.

## Version catalog

- **Every version, library, and plugin lives in `gradle/libs.versions.toml`.** No inline `"group:name:version"` strings and no plugin version literals in module scripts.
- Shared versions use `version.ref`; groups always declared together get a `[bundles]` entry.
- Migrate a project to the catalog in one change, not module by module.

## Toolchain and SDK levels

- **AGP, Kotlin, and the Compose compiler move together.** On Kotlin 2.0+, use the `org.jetbrains.kotlin.plugin.compose` plugin and never set `kotlinCompilerExtensionVersion`.
- **`kotlin { jvmToolchain(17) }`**, not `compileOptions` / `kotlinOptions.jvmTarget`.
- `compileSdk` is the newest tested API; raise `targetSdk` deliberately (it changes runtime behavior); pick `minSdk` on purpose. `namespace` and `applicationId` are different things.

## Dependencies

- **`implementation` by default; `api` only when your public signatures expose the dependency's types.** `compileOnly` only for compile-time-only libraries.
- **KSP, not kapt**, for Hilt, Room, and Moshi.
- Libraries that ship reflection-based types publish keep rules with `consumerProguardFiles("consumer-rules.pro")`.
- `includeBuild` / `mavenLocal()` for local sibling work never reach a release branch.

## Committed files

- **Commit** `gradle/wrapper/` (properties and jar), and `gradle.lockfile` for apps that lock dependencies. Libraries don't lock.
- **Never commit** `local.properties`, `build/`, or per-developer `.idea/` files.
- Lint, format, coverage, and docs plugins (ktlint, detekt, JaCoCo, Dokka) come from the catalog too.
