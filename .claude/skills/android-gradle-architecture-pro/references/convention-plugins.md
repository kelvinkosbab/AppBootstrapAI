# Convention Plugins (`build-logic/convention/`)

Convention plugins are the Now in Android pattern for **factoring repeated build configuration**. Instead of every module's `build.gradle.kts` containing the same `android { compileSdk = 34; defaultConfig { minSdk = 26; ... } }` block, that block lives in a Kotlin class that modules apply by name.

Reference: [`build-logic/convention/`](https://github.com/android/nowinandroid/tree/main/build-logic/convention) in Now in Android.

## Why a composite build (not `buildSrc/`)

Two reasons:

1. **`buildSrc/` invalidates Gradle's configuration cache too aggressively** — any change to `buildSrc/` re-runs every module's configuration phase. `build-logic/` via `includeBuild(...)` does not.
2. **`build-logic/` is more modular.** Multiple repos can share the same `build-logic/` shape; `buildSrc/` is per-project by design.

The downside: `build-logic/` requires its own `settings.gradle.kts` and `build.gradle.kts`, slightly more setup. Worth it past 3 modules.

## Layout

```
build-logic/
├── settings.gradle.kts            # composite-build settings
├── convention/
│   ├── build.gradle.kts           # convention module's build script
│   └── src/main/kotlin/
│       ├── AndroidApplicationConventionPlugin.kt
│       ├── AndroidApplicationComposeConventionPlugin.kt
│       ├── AndroidLibraryConventionPlugin.kt
│       ├── AndroidLibraryComposeConventionPlugin.kt
│       ├── AndroidFeatureConventionPlugin.kt
│       ├── AndroidHiltConventionPlugin.kt
│       ├── AndroidTestConventionPlugin.kt
│       └── ... (one per common module shape)
└── README.md
```

## Minimal `build-logic/settings.gradle.kts`

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
    // Re-use the same libs.versions.toml as the parent project
    versionCatalogs {
        create("libs") {
            from(files("../gradle/libs.versions.toml"))
        }
    }
}

rootProject.name = "build-logic"
include(":convention")
```

The `from(files("../gradle/libs.versions.toml"))` line is how `build-logic/` shares the parent project's version catalog. Without it, plugin authors can't reference `libs.versions.android.compileSdk.get()` from inside the plugin classes.

## Minimal `build-logic/convention/build.gradle.kts`

```kotlin
plugins {
    `kotlin-dsl`
}

group = "com.kozinga.buildlogic"

// Convention plugins compile against the AGP and Kotlin plugin APIs.
dependencies {
    compileOnly(libs.android.gradle.plugin)
    compileOnly(libs.kotlin.gradle.plugin)
    compileOnly(libs.compose.gradle.plugin)   // only if you use the Compose Compiler plugin
    compileOnly(libs.ksp.gradle.plugin)
}

// Register the plugin IDs so modules can apply via alias(libs.plugins.kozinga.android.application).
gradlePlugin {
    plugins {
        register("androidApplication") {
            id = "kozinga.android.application"
            implementationClass = "AndroidApplicationConventionPlugin"
        }
        register("androidLibrary") {
            id = "kozinga.android.library"
            implementationClass = "AndroidLibraryConventionPlugin"
        }
        register("androidFeature") {
            id = "kozinga.android.feature"
            implementationClass = "AndroidFeatureConventionPlugin"
        }
        register("androidLibraryCompose") {
            id = "kozinga.android.library.compose"
            implementationClass = "AndroidLibraryComposeConventionPlugin"
        }
        register("androidHilt") {
            id = "kozinga.android.hilt"
            implementationClass = "AndroidHiltConventionPlugin"
        }
    }
}
```

You'll also need matching entries in `gradle/libs.versions.toml`:

```toml
[plugins]
android-gradle-plugin = { id = "com.android.tools.build:gradle", version.ref = "agp" }
kotlin-gradle-plugin  = { id = "org.jetbrains.kotlin:kotlin-gradle-plugin", version.ref = "kotlin" }

# Convention plugins — referenced by feature/library modules via alias(libs.plugins...)
kozinga-android-application         = { id = "kozinga.android.application",          version = "unspecified" }
kozinga-android-library             = { id = "kozinga.android.library",              version = "unspecified" }
kozinga-android-feature             = { id = "kozinga.android.feature",              version = "unspecified" }
kozinga-android-library-compose     = { id = "kozinga.android.library.compose",      version = "unspecified" }
kozinga-android-hilt                = { id = "kozinga.android.hilt",                 version = "unspecified" }
```

The `version = "unspecified"` is intentional — convention plugins don't ship as artifacts; they're loaded from the composite build.

## A real convention plugin: `AndroidLibraryConventionPlugin.kt`

```kotlin
import com.android.build.gradle.LibraryExtension
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.kotlin.dsl.configure
import org.gradle.kotlin.dsl.dependencies

class AndroidLibraryConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            with(pluginManager) {
                apply("com.android.library")
                apply("org.jetbrains.kotlin.android")
            }

            extensions.configure<LibraryExtension> {
                compileSdk = 34
                defaultConfig {
                    minSdk = 26
                    testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
                }
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
                buildFeatures {
                    buildConfig = false   // disable unless you actually need it
                }
            }
        }
    }
}
```

Then a module that wants this shape only writes:

```kotlin
// feature/home/build.gradle.kts
plugins {
    alias(libs.plugins.kozinga.android.library)
}

android {
    namespace = "com.kozinga.feature.home"
}

dependencies {
    implementation(project(":core:ui"))
    // ...
}
```

## NiA's plugin set

| Plugin | What it applies | When to apply |
|--------|-----------------|---------------|
| `AndroidApplicationConventionPlugin` | `com.android.application`, Kotlin Android, base `android {}` for the app | `:app` only |
| `AndroidLibraryConventionPlugin` | `com.android.library`, Kotlin Android, base `android {}` for libraries | Most modules |
| `AndroidFeatureConventionPlugin` | Library + Hilt + common test deps | `:feature:*` modules |
| `AndroidApplicationComposeConventionPlugin` | Application + Compose Compiler plugin + Compose buildFeatures | `:app` if using Compose |
| `AndroidLibraryComposeConventionPlugin` | Library + Compose Compiler plugin + Compose buildFeatures | Library modules using Compose |
| `AndroidHiltConventionPlugin` | Hilt plugin + KSP + Hilt dependencies | Any module that needs DI |
| `AndroidApplicationJacocoConventionPlugin` | JaCoCo configuration for app coverage | `:app` for coverage |
| `JvmLibraryConventionPlugin` | Pure-Kotlin library (no Android dependencies) | `:core:common` style modules |

## When to extract a convention plugin

- **Three or more modules duplicate a config block** — extract.
- **Onboarding a new feature module is more than 20 lines of `build.gradle.kts`** — extract.
- **Bumping `minSdk` requires edits in N places** — extract; bump once in the plugin.
- **Single-module project** — don't extract. Convention plugins are overhead until they save real duplication.

## Common pitfalls

- **Forgetting `from(files("../gradle/libs.versions.toml"))`** in `build-logic/settings.gradle.kts` — plugins can't see `libs` and you write hardcoded versions inside the plugin classes (defeating catalog discipline).
- **Convention plugin doing too much** — one plugin should set up one logical thing (Compose, Hilt, JaCoCo). Resist the `KitchenSinkPlugin`.
- **Modules `apply(plugin = "...")` instead of `alias(libs.plugins...)`** — works but bypasses the catalog. Always alias.
- **Convention plugin depending on a sibling convention plugin via `apply(plugin = "kozinga.android.library")` from inside another plugin** — works but creates plugin-application order surprises. Prefer composing via `pluginManager.apply(...)` at the top of each plugin's `apply()` method.
- **Putting `dependencies { }` blocks in convention plugins for *module-specific* deps** — only put dependencies that *every* module of that shape needs (e.g., `androidx.lifecycle.runtime.ktx` for `AndroidFeatureConventionPlugin`). Feature-specific deps stay in the module.

## Smaller pattern for smaller projects

For a 2-3 module project where a full `build-logic/` is overkill, you can still factor a single `extensions.kt` file in the root with extension functions on `Project` — applied via `subprojects { afterEvaluate { configureCommonAndroid() } }` in the root `build.gradle.kts`. Less powerful, less invalidation-friendly, but lower overhead.

That said: as soon as you hit 3 feature modules, jump to convention plugins. The migration cost is small, the maintenance benefit is large.
