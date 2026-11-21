# Android Library Module Setup

## Pick the module type

| Code | Module | Artifact |
|---|---|---|
| Uses Android APIs, resources, or Compose | `com.android.library` | AAR |
| Pure Kotlin / Java, no Android APIs | `org.jetbrains.kotlin.jvm` (`java-library`) | JAR, usable by Android and server apps |
| Shared with iOS or other targets | Kotlin Multiplatform with `com.android.kotlin.multiplatform.library` for the Android target | KLIB + AAR |

Don't ship an AAR for code that has no Android dependency: a JAR is faster to build, testable without Robolectric, and usable in more places.

## `build.gradle.kts`

```kotlin
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlinx.binary.compatibility.validator) // or KGP abiValidation, see api-and-abi.md
    alias(libs.plugins.dokka)
    alias(libs.plugins.vanniktech.maven.publish)              // see publishing.md
}

android {
    namespace = "com.example.widgets"
    compileSdk = 36
    resourcePrefix = "widgets_"

    defaultConfig {
        minSdk = 23
        consumerProguardFiles("consumer-rules.pro")
        aarMetadata {
            minCompileSdk = 34 // only if consumers truly need it, e.g. you reference newer platform APIs in public signatures
        }
    }

    lint { targetSdk = 36 }
    testOptions { targetSdk = 36 }

    buildTypes {
        release { isMinifyEnabled = false } // the app's R8 shrinks the library
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

kotlin {
    explicitApi()
    jvmToolchain(17)                 // JDK used to build
    compilerOptions {
        jvmTarget = JvmTarget.JVM_11 // bytecode consumers must accept
        apiVersion = KotlinVersion.KOTLIN_2_0
        languageVersion = KotlinVersion.KOTLIN_2_0
    }
    coreLibrariesVersion = "2.0.21" // kotlin-stdlib version written to the POM
}

dependencies {
    api(libs.androidx.annotation)        // appears in public signatures
    implementation(libs.androidx.core.ktx)
    testImplementation(libs.junit)
}
```

### Why each setting

- **`namespace`** generates `R` and `BuildConfig` packages; the manifest `package` attribute is gone.
- **No `targetSdk`**: in a library it only affects tests and lint, and the DSL entry is deprecated for libraries. The app's `targetSdk` governs runtime behavior.
- **`minSdk` as low as you really support**: a library's `minSdk` above an app's fails the app's manifest merge. Test on the lowest API level in CI (an emulator job or Robolectric with `@Config(sdk = [23])`).
- **`resourcePrefix`** makes lint flag any resource without the prefix. Unprefixed library resources silently override, or are overridden by, the app's resources of the same name.
- **Non-transitive R** (`android.nonTransitiveRClass=true`, the default since AGP 8) keeps your `R` class to your own resources.
- **`aarMetadata.minCompileSdk`** makes consumers' builds fail early with a clear message instead of a confusing compile error. Don't raise it casually: it forces every consumer's `compileSdk` up.
- **Kotlin floors**: by default the compiler writes metadata for its own version and depends on its own stdlib, so a library built with a new Kotlin can force every consumer to upgrade their compiler. `apiVersion` / `languageVersion` limit the language and stdlib API you use, and `coreLibrariesVersion` sets the stdlib dependency version. Keep them at the oldest Kotlin you promise to support and test with it.
- **Java bytecode target**: 11 is a safe default for Android libraries in 2026; 17 is fine if all your consumers build with AGP 8+. A higher target than consumers desugar breaks their builds.
- **`isMinifyEnabled = false`**: minifying a library renames public API and duplicates work the app does anyway.

### `api` vs `implementation`

- `api(dep)` puts `dep` on consumers' compile classpath and in the POM's `compile` scope. Use it only when a type from `dep` appears in your public signatures (parameters, return types, supertypes, public properties).
- Everything else is `implementation` (POM `runtime` scope).
- Each dependency is a version constraint on the app. Prefer fewer: an `androidx.core` utility you can write in ten lines is not worth the edge.
- Never publish with `-SNAPSHOT`, `+`, or `latest.release` dependency versions.

## Consumer rules and lint

- `consumer-rules.pro` holds keep rules for reflection your code does (serializers, `Class.forName`, JNI). Full guidance: `r8-shrink-pro/references/consumer-rules.md`.
- Never put global options in consumer rules: `-dontobfuscate`, `-dontoptimize`, `-dontshrink`, `-allowaccessmodification`, `-repackageclasses`, `-printmapping`. They change every consuming app's build, and recent AGP versions warn about or ignore them.
- Keep rules are scoped to your own packages (`-keep class com.example.widgets.internal.Serializer { *; }`), never `-keep class ** { *; }`.
- Custom lint checks that guide consumers (wrong API usage) ship inside the AAR: put them in a `com.android.lint` / JVM module and add `lintPublish(project(":widgets-lint"))`.

## Testing

- **Tests use the public API.** A module-internal test can see `internal` members; add at least one test source set or the sample app that compiles against the public surface only.
- **Test fixtures for consumers**: `android { testFixtures { enable = true } }` publishes a `test-fixtures` variant with fakes consumers can use in their tests. A separate `widgets-testing` artifact works too and is clearer to discover.
- **Sample app** (`:sample`, `com.android.application`) that depends on the library like a consumer would (`implementation(project(":widgets"))`), built in CI, never published.
- **Instrumented tests on the lowest and newest API** you support for anything touching platform APIs.

## Compose libraries

- Composables take `modifier: Modifier = Modifier` as the first optional parameter and apply it to the root.
- Parameters are stable types: immutable data, `@Immutable` / `@Stable` classes, `ImmutableList` or a stability config. Unstable parameters make every consumer screen recompose more.
- Slot APIs (`content: @Composable () -> Unit`) over boolean flags; a `XxxDefaults` object for colors, sizes, and shapes.
- Take colors and typography from `MaterialTheme` (or your own `CompositionLocal` with a fail-loud default), never hardcode them.
- No `ViewModel`, `Context`, navigation, or DI framework dependency in components.
- Depend on Compose BOM artifacts as `api` only when they appear in signatures (they usually do: `Modifier`, `Color`).
- Generate Compose compiler reports in CI (`composeCompiler { reportsDestination = … }`) to catch unstable public parameters.

## Multi-module libraries

- Each published module gets its own artifact ID with a shared group and version.
- Publish a BOM (`java-platform` module) listing them so consumers align versions (`publishing.md`).
- Internal-only modules that published modules depend on must be published too, or merged in; an unpublished project dependency produces a POM pointing at an artifact that doesn't exist.
