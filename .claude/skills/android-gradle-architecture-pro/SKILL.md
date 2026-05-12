---
name: android-gradle-architecture-pro
description: Reviews multi-module Android Gradle builds against the Now in Android convention-plugin pattern — `build-logic/convention/` factoring, version-catalog discipline, AGP/Kotlin/Compose-compiler co-versioning, KSP over kapt. Use when reading, writing, or reviewing Gradle build files in non-trivial Android projects.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "Android 'Now in Android' (https://github.com/android/nowinandroid), Android Developers docs for AGP 8.x"
---

Review Android Gradle build configuration for adherence to modern multi-module conventions. The reference pattern is **[Now in Android (NiA)](https://github.com/android/nowinandroid)** — Google's official reference app — which factors all repeated `android { ... }` and dependency declarations into **convention plugins** under `build-logic/convention/`. Report only genuine problems; don't nitpick.

Review process:

1. Inventory the build-file landscape using `references/inventory.md` — which files exist, what each is responsible for.
2. Check the convention-plugin factoring using `references/convention-plugins.md` — is repeated config extracted? Where does it live?
3. Validate version-catalog discipline using `references/version-catalogs.md` — no inline `implementation("group:artifact:version")` strings, no hardcoded versions in `build.gradle.kts`.
4. Validate the multi-module graph using `references/multi-module-graph.md` — `:app` + `:feature:*` + `:data:*` + `:core:*` shape, dependency direction.
5. Check AGP / Kotlin / Compose-compiler co-versioning using `references/agp-versioning.md`.
6. Verify KSP is used over kapt for all supported annotation processors using `references/ksp-over-kapt.md`.

If doing a partial review, load only the relevant reference files.

## Core Instructions

- **Now in Android is the reference.** When in doubt, check what NiA does. Their convention plugins under [`build-logic/convention/`](https://github.com/android/nowinandroid/tree/main/build-logic/convention) are the canonical examples.
- **Convention plugins are non-negotiable past 3 modules.** Once you have a `:feature:home`, `:feature:settings`, `:feature:profile`, the third repeated `android { compileSdk = 34; defaultConfig { minSdk = 26; ... } }` block is a smell. Factor.
- **Version catalogs are the single source of truth.** Every version literal in a `build.gradle.kts` is a regression — there's always a `[versions]` entry it should reference.
- **AGP version is grounded in AGP 8.x** for this skill. AGP 9 specifics are unverified; if the project uses AGP 9, defer to the actual release notes rather than this skill's guidance.
- **Don't suggest applying convention plugins where they're not warranted.** A single-module app doesn't need `build-logic/convention/`. Convention plugins are a multi-module concern.
- **Don't introduce `buildSrc/` for new code.** The `build-logic/` composite-build pattern superseded `buildSrc` because the latter invalidates Gradle's cache more aggressively. NiA uses `build-logic`; new projects should too.

## Output Format

Organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after.

Skip files with no issues. End with a prioritized summary.

Example output:

### feature/home/build.gradle.kts

**Line 12: Repeated `android { }` block — extract to a convention plugin.**

```kotlin
// Before
android {
    namespace = "com.kozinga.feature.home"
    compileSdk = 34
    defaultConfig { minSdk = 26 }
    buildFeatures { compose = true }
}

// After
plugins {
    alias(libs.plugins.kozinga.android.feature)
    alias(libs.plugins.kozinga.android.library.compose)
}

android {
    namespace = "com.kozinga.feature.home"
}
```

**Line 28: Inline dependency string — use the version catalog.**

```kotlin
// Before
implementation("androidx.core:core-ktx:1.15.0")

// After
implementation(libs.androidx.core.ktx)
```

### build-logic/convention/build.gradle.kts (missing)

**No `build-logic/` convention-plugin module — three feature modules repeat the same `android {}` block. Create `build-logic/convention/` and factor `AndroidFeatureConventionPlugin`.**

### Summary

1. **Architecture (high):** No convention plugins; three `:feature:*` modules duplicate `android {}` configuration.
2. **Catalog discipline (medium):** Four inline dependency strings across `feature/home/build.gradle.kts` and `feature/settings/build.gradle.kts` — migrate to `libs.versions.toml`.
3. **kapt → KSP (low):** `kapt` for Hilt — switch to `ksp(libs.hilt.compiler)` for faster builds.

End of example.

## References

- `references/inventory.md` — what every Android Gradle file is responsible for (`settings.gradle.kts`, root `build.gradle.kts`, module `build.gradle.kts`, `libs.versions.toml`, `gradle.properties`, `build-logic/`).
- `references/convention-plugins.md` — how to author a convention plugin in `build-logic/convention/`, the NiA factoring (`AndroidApplicationConventionPlugin`, `AndroidLibraryConventionPlugin`, `AndroidComposeConventionPlugin`, `AndroidFeatureConventionPlugin`, `AndroidHiltConventionPlugin`, `AndroidApplicationJacocoConventionPlugin`).
- `references/version-catalogs.md` — `libs.versions.toml` depth, `[bundles]`, plugin entries, migration patterns from inline strings.
- `references/multi-module-graph.md` — `:app` + `:feature:*` + `:data:*` + `:core:*` shape, dependency direction, how features avoid depending on each other.
- `references/agp-versioning.md` — AGP/Kotlin/Compose-compiler version matrix (AGP 8.x), the Kotlin 2.0+ Compose plugin model, common upgrade pitfalls.
- `references/ksp-over-kapt.md` — KSP-first stance for Hilt / Room / Moshi / Glide, what migration looks like, what still requires kapt.
