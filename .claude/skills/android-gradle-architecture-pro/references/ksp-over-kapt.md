# KSP Over kapt

KSP (Kotlin Symbol Processing) is the modern annotation-processor API for Kotlin. It's faster than kapt (no Java stub generation), produces incremental builds, and is the official direction for Kotlin tooling.

**Rule: use KSP for every annotation processor that supports it.** kapt is on a deprecation path.

## What supports KSP (as of Kotlin 2.0.x)

| Library | KSP support | Migration status |
|---------|-------------|------------------|
| Hilt (Dagger) | Yes | Stable since Dagger 2.48 |
| Room | Yes | Stable since Room 2.6 |
| Moshi | Yes | Stable since Moshi 1.15 |
| Glide | Yes | Stable |
| AndroidX Navigation | N/A (uses gradle plugin) | n/a |
| Anvil | Partial | Watch upstream |
| Realm | No | Still kapt-only — accept it |

When in doubt, check the library's docs. Most major libraries have a "KSP migration" page.

## What KSP changes in `build.gradle.kts`

### Before (kapt)

```kotlin
plugins {
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.kapt)
}

dependencies {
    implementation(libs.hilt.android)
    kapt(libs.hilt.compiler)

    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    kapt(libs.androidx.room.compiler)

    implementation(libs.moshi)
    kapt(libs.moshi.codegen)
}
```

### After (KSP)

```kotlin
plugins {
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.ksp)
}

dependencies {
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)

    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)

    implementation(libs.moshi)
    ksp(libs.moshi.codegen)
}
```

Three differences:

1. **Plugin:** `kotlin-kapt` → `ksp`.
2. **Configuration:** `kapt(...)` → `ksp(...)`.
3. **Compiler artifact may have a different coordinate.** For Moshi, `moshi-kotlin-codegen` works for both; for Hilt, `hilt-android-compiler` works for both; for Room, `room-compiler` works for both. Check each library.

## Catalog entries

```toml
[versions]
ksp = "2.0.21-1.0.28"
hilt = "2.52"
room = "2.6.1"
moshi = "1.15.1"

[libraries]
hilt-android       = { group = "com.google.dagger",    name = "hilt-android",      version.ref = "hilt" }
hilt-compiler      = { group = "com.google.dagger",    name = "hilt-android-compiler", version.ref = "hilt" }
room-runtime       = { group = "androidx.room",        name = "room-runtime",      version.ref = "room" }
room-ktx           = { group = "androidx.room",        name = "room-ktx",          version.ref = "room" }
room-compiler      = { group = "androidx.room",        name = "room-compiler",     version.ref = "room" }
moshi              = { group = "com.squareup.moshi",   name = "moshi",             version.ref = "moshi" }
moshi-codegen      = { group = "com.squareup.moshi",   name = "moshi-kotlin-codegen", version.ref = "moshi" }

[plugins]
ksp                = { id = "com.google.devtools.ksp", version.ref = "ksp" }
```

## What KSP doesn't replace

- **Plugin-based code generators** (AndroidX Navigation, kotlinx-serialization) — these are Gradle plugins, not annotation processors. No kapt-vs-KSP question.
- **`@JvmField` / `@JvmStatic` and similar Kotlin-to-Java interop annotations** — handled by the Kotlin compiler, not an annotation processor.
- **Macro-like sources from kotlin compiler plugins** (e.g., Compose) — also compiler plugins, not annotation processors.

## Build performance

For a medium Android project (~50 modules, mixed Hilt/Room/Moshi codegen), the KSP migration commonly saves **25–40% on clean build time** and improves incremental build hit rates significantly. The win compounds with parallel builds enabled.

## Migration checklist

When converting a module from kapt to KSP:

1. **Confirm every processor supports KSP** — if even one still requires kapt, you have to keep both plugins applied for that module. Rare but possible (legacy Realm, niche custom processors).
2. **Apply the `ksp` plugin** (`alias(libs.plugins.ksp)`) in the module.
3. **Remove the `kotlin-kapt` plugin** if all processors moved.
4. **Replace `kapt(...)` → `ksp(...)`** for each processor dependency.
5. **Update the compiler artifact coordinate** if the library's KSP variant is named differently (most aren't, but check).
6. **Rebuild and check for errors** — KSP sometimes catches things kapt let slide (notably, Hilt configurations that worked in kapt but fail under KSP's stricter analysis).
7. **Compare generated code** in `build/generated/ksp/<variant>/kotlin/` to spot differences (rare, but possible).

## Common pitfalls

- **Forgetting to apply the `ksp` plugin** while using `ksp(...)` in dependencies — Gradle silently doesn't run the processor. Hilt-generated `_Factory` classes won't exist; runtime crashes with `ClassNotFoundException` for `*_Factory`.
- **Mixed kapt + KSP for the same processor** — pick one. Some libraries support both, but running both means double-processing, slower builds, and occasional generated-file conflicts.
- **Module-specific KSP options needed** — set via `ksp { arg("room.schemaLocation", "$projectDir/schemas") }` in the module's `build.gradle.kts`. The `room.schemaLocation` option, for instance, often confuses developers when they don't see schemas generated.
- **KSP version drift from Kotlin** — KSP version embeds Kotlin version. Bump them together.
- **Convention plugin assumes kapt** — if `AndroidHiltConventionPlugin.kt` applies `kotlin-kapt`, it's old. Update it to apply `ksp`.

## Hilt convention plugin (KSP edition)

```kotlin
class AndroidHiltConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            with(pluginManager) {
                apply("com.google.devtools.ksp")
                apply("dagger.hilt.android.plugin")
            }

            dependencies {
                add("implementation", libs.findLibrary("hilt-android").get())
                add("ksp", libs.findLibrary("hilt-compiler").get())
            }
        }
    }
}
```

(`libs` is accessible inside convention plugins via `project.extensions.getByType<VersionCatalogsExtension>().named("libs")`, then `.findLibrary(...).get()` for each artifact. NiA has a helper for this.)
