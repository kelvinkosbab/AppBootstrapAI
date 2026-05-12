# Version Catalogs (`gradle/libs.versions.toml`)

The single source of truth for dependency and plugin versions. Gradle auto-discovers `gradle/libs.versions.toml` and exposes it as the `libs` accessor in every `build.gradle.kts`.

This reference goes deeper than the `android-gradle-conventions.md` rule — focus is on **structure, bundles, migration patterns, and review checks**.

## Four sections of `libs.versions.toml`

```toml
[versions]
# Every version literal — keyed.

[libraries]
# Every dependency artifact.

[plugins]
# Every Gradle plugin.

[bundles]
# Groups of libraries that always go together.
```

## `[versions]` — naming and grouping

- **Group versions that move together** with a shared prefix:

  ```toml
  [versions]
  androidx-lifecycle = "2.8.7"
  androidx-lifecycle-compose = "2.8.7"   # bumps with the parent
  androidx-compose-bom = "2024.10.01"
  androidx-compose-material3 = "1.3.1"   # tracks the BOM
  ```

- **Don't reuse the same `[versions]` key for unrelated libraries** that happen to have the same version today — they'll drift in the next bump.
- **Major sibling versions deserve their own key** (`hilt = "2.52"`, `hilt-navigation = "1.2.0"`) — Hilt and Hilt-Navigation-Compose are released independently.

## `[libraries]` — keys become dotted accessors

Hyphens in keys become dots in code:

```toml
androidx-core-ktx              = { ... }   # → libs.androidx.core.ktx
androidx-lifecycle-runtime-ktx = { ... }   # → libs.androidx.lifecycle.runtime.ktx
hilt-android                   = { ... }   # → libs.hilt.android
```

- **Prefix accessors by ecosystem** (`androidx-*`, `hilt-*`, `kotlinx-*`) so autocomplete groups them.
- **Don't truncate** — `lifecycle = ...` is too vague when you also have `lifecycle-viewmodel`, `lifecycle-runtime`, `lifecycle-process`. Be specific.

## `[plugins]` — version + id

Plugins follow the same convention:

```toml
[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
android-library     = { id = "com.android.library", version.ref = "agp" }
kotlin-android      = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
kotlin-compose      = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
hilt                = { id = "com.google.dagger.hilt.android", version.ref = "hilt" }
ksp                 = { id = "com.google.devtools.ksp", version.ref = "ksp" }
```

Then apply in a module:

```kotlin
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}
```

## `[bundles]` — groups that ship together

```toml
[bundles]
androidx-lifecycle = [
    "androidx-lifecycle-runtime-ktx",
    "androidx-lifecycle-runtime-compose",
    "androidx-lifecycle-viewmodel-ktx",
    "androidx-lifecycle-viewmodel-compose"
]
compose-ui = [
    "androidx-compose-ui",
    "androidx-compose-ui-tooling-preview",
    "androidx-compose-material3"
]
```

```kotlin
dependencies {
    implementation(libs.bundles.androidx.lifecycle)
    implementation(libs.bundles.compose.ui)
}
```

**Use bundles only for libraries that always travel together.** A bundle that's "almost always" used but sometimes excluded creates friction — you end up declaring the bundle then excluding members, which is messier than just declaring the libraries individually.

## Migration: from inline strings to the catalog

Common starting state (from `swift package init`–era Android equivalents):

```kotlin
// Before
dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("com.google.dagger:hilt-android:2.52")
    kapt("com.google.dagger:hilt-android-compiler:2.52")
}
```

Migration steps:

1. **Extract every version literal** into `[versions]`:

    ```toml
    [versions]
    androidx-core = "1.15.0"
    androidx-lifecycle = "2.8.7"
    androidx-activity-compose = "1.9.3"
    androidx-compose-bom = "2024.10.01"
    hilt = "2.52"
    ```

2. **Add each artifact to `[libraries]`**:

    ```toml
    [libraries]
    androidx-core-ktx              = { group = "androidx.core",       name = "core-ktx",       version.ref = "androidx-core" }
    androidx-lifecycle-runtime-ktx = { group = "androidx.lifecycle",  name = "lifecycle-runtime-ktx", version.ref = "androidx-lifecycle" }
    androidx-activity-compose      = { group = "androidx.activity",   name = "activity-compose", version.ref = "androidx-activity-compose" }
    androidx-compose-bom           = { group = "androidx.compose",    name = "compose-bom",     version.ref = "androidx-compose-bom" }
    androidx-compose-ui            = { group = "androidx.compose.ui", name = "ui" }
    androidx-compose-material3     = { group = "androidx.compose.material3", name = "material3" }
    hilt-android                   = { group = "com.google.dagger",   name = "hilt-android",    version.ref = "hilt" }
    hilt-compiler                  = { group = "com.google.dagger",   name = "hilt-android-compiler", version.ref = "hilt" }
    ```

    Note Compose-via-BOM artifacts (`androidx-compose-ui`, `androidx-compose-material3`) have no version — the BOM resolves them.

3. **Rewrite the module's `dependencies {}`**:

    ```kotlin
    // After
    dependencies {
        implementation(libs.androidx.core.ktx)
        implementation(libs.androidx.lifecycle.runtime.ktx)
        implementation(libs.androidx.activity.compose)
        implementation(platform(libs.androidx.compose.bom))
        implementation(libs.androidx.compose.ui)
        implementation(libs.androidx.compose.material3)
        implementation(libs.hilt.android)
        ksp(libs.hilt.compiler)   // ksp not kapt
    }
    ```

4. **Repeat for every module.** A 5-module project takes 30 minutes the first time; subsequent dep additions are now one TOML edit + one module edit.

## Review checks

When reviewing a module's `build.gradle.kts` for catalog discipline:

- **Zero inline `implementation("group:name:version")` strings.** Every dependency through `libs.*`.
- **Zero hardcoded version literals** anywhere in `build.gradle.kts` (`compileSdk = 34` is fine if it's in a convention plugin and centralized).
- **Bundles used where applicable** — a module that pulls 4 lifecycle artifacts individually should use `libs.bundles.androidx.lifecycle`.
- **`[versions]` keys grouped** — coordinated bumps stay coordinated.
- **`version.ref` vs `version =`** — `version.ref` for shared versions, literal `version =` only when truly unique to one artifact.

## Common pitfalls

- **Hyphen-vs-dot confusion** — `androidx-core-ktx` in TOML maps to `libs.androidx.core.ktx` in code. If you read `libs.androidx_core_ktx`, that's wrong.
- **Same version in multiple `[versions]` keys** — `kotlin = "2.0.21"` and `kotlin-compiler = "2.0.21"` will drift. Use `version.ref = "kotlin"` for the second.
- **BOM platform missed** — `implementation(platform(libs.androidx.compose.bom))` is required for Compose; forgetting it means individual Compose artifacts can't resolve.
- **Plugin version literal in `build.gradle.kts`** — `alias(libs.plugins.X)` is the only form. If you see `id("com.android.application") version "8.7.0"` in a module script, that's the smell.
- **Catalog file in the wrong location** — must be `gradle/libs.versions.toml`. Gradle won't auto-discover it from elsewhere.
- **Old format `androidx-core-ktx = "androidx.core:core-ktx:1.15.0"`** (the legacy shorthand syntax) — works but harder to migrate to `version.ref`. Use the `{ group, name, version.ref }` form for everything.
