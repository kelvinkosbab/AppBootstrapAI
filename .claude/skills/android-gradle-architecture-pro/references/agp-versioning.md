# AGP / Kotlin / Compose-Compiler Co-Versioning

These three move in lockstep. Mismatched versions surface as confusing compiler errors that look like everything else but aren't.

**Scope of this reference:** AGP 8.x. AGP 9 specifics are unverified; if a project uses AGP 9, consult [the actual release notes](https://developer.android.com/build/releases/gradle-plugin) rather than this skill.

## The three things that have to agree

| Thing | Catalog key | Why it matters |
|-------|-------------|----------------|
| AGP (Android Gradle Plugin) | `agp` | Determines available `android {}` API surface, Gradle compatibility |
| Kotlin | `kotlin` | Determines Kotlin language version, stdlib API |
| Compose Compiler | (auto via plugin in Kotlin 2.0+) | Must match the Kotlin version that produced the bytecode |

## Kotlin 2.0+ (current, recommended)

The Compose Compiler is now a **Kotlin compiler plugin**, applied via the `org.jetbrains.kotlin.plugin.compose` plugin:

```toml
# libs.versions.toml
[versions]
agp = "8.7.0"
kotlin = "2.0.21"

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
android-library     = { id = "com.android.library", version.ref = "agp" }
kotlin-android      = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
kotlin-compose      = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }   # ← here
```

```kotlin
// module/build.gradle.kts
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)   // No need to manually set kotlinCompilerExtensionVersion
}

android {
    buildFeatures { compose = true }
    // No composeOptions { kotlinCompilerExtensionVersion = ... } block needed
}
```

The Compose Compiler version is determined by the Kotlin version — Kotlin 2.0.21 ships with a specific Compose Compiler that's already correct. **Don't set `composeOptions.kotlinCompilerExtensionVersion` manually under Kotlin 2.0+** — it fights the plugin.

## Pre-Kotlin 2.0 (legacy projects)

If your project is on Kotlin 1.9.x or earlier, the Compose Compiler is a *separate library* pinned independently:

```toml
[versions]
agp = "8.2.2"
kotlin = "1.9.25"
compose-compiler = "1.5.15"   # ← independent pin

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
kotlin-android      = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
# No kotlin-compose plugin under Kotlin 1.x
```

```kotlin
android {
    buildFeatures { compose = true }
    composeOptions {
        kotlinCompilerExtensionVersion = libs.versions.compose.compiler.get()
    }
}
```

The version pairing is rigid. **Use [the Compose-to-Kotlin compatibility map](https://developer.android.com/jetpack/androidx/releases/compose-kotlin)** to pick the right Compose Compiler for your Kotlin version. Get it wrong and you get errors like `This version of Compose Compiler requires Kotlin version X.Y.Z` at compile time.

## AGP version selection

AGP versions track Android Studio releases:

| Android Studio | AGP version | Required Gradle | JDK |
|---------------|-------------|----------------|-----|
| Koala (2024.1.x) | 8.5.x | 8.7+ | 17 |
| Ladybug (2024.2.x) | 8.7.x | 8.9+ | 17 |
| Meerkat (2024.3.x) | 8.8.x | 8.10+ | 17 |

(Exact versions shift as Studio releases; verify against Android Studio's current install.)

- **Pin AGP to a version that matches the team's installed Studio** — not bleeding-edge. A team on Ladybug compiling against AGP 8.8 occasionally hits "AGP requires Studio X+" warnings.
- **Bump AGP deliberately** — not opportunistically. AGP bumps sometimes change behavior (e.g., `namespace` becoming mandatory in 8.0, `R8 full mode` becoming default).

## Gradle wrapper version

`gradle/wrapper/gradle-wrapper.properties` pins the Gradle version. AGP has a minimum:

```
distributionUrl=https\://services.gradle.org/distributions/gradle-8.10-bin.zip
```

- **AGP 8.7 requires Gradle 8.9+** (approximate; verify in AGP release notes).
- **Update Gradle and AGP in the same PR** so reviewers see the matched pair.
- **Use `./gradlew wrapper --gradle-version <new>`** to update — don't hand-edit `gradle-wrapper.properties`.

## JDK / `jvmToolchain`

```kotlin
// module/build.gradle.kts (or in a convention plugin)
kotlin {
    jvmToolchain(17)
}
```

- **JDK 17 is the AGP 8.x baseline.** JDK 21 works for newer AGP versions; check release notes.
- **`jvmToolchain(N)` replaces both `compileOptions.sourceCompatibility/targetCompatibility` and `kotlinOptions.jvmTarget`** — don't mix.
- **Gradle downloads the JDK** if it's not installed locally. Convenient but slow first time; CI should pre-warm.

## KSP version

KSP version embeds the Kotlin version it matches:

```toml
[versions]
kotlin = "2.0.21"
ksp = "2.0.21-1.0.28"   # ← Kotlin version + KSP suffix
```

The `2.0.21` prefix must match `kotlin` exactly. KSP 1.0.28 is the matching KSP minor; check [KSP releases](https://github.com/google/ksp/releases) for the current pairing.

When you bump Kotlin, **bump KSP in the same edit**. A common mistake: bump Kotlin and forget KSP, see KSP fail with "KSP requires Kotlin X.Y.Z, got A.B.C."

## Common pitfalls

- **Setting `composeOptions.kotlinCompilerExtensionVersion` under Kotlin 2.0+** — fights the new Compose plugin model. Remove.
- **Kotlin and KSP version drift** — KSP is the most common "I forgot to bump" issue. Bump together.
- **AGP bumped without matching Gradle wrapper bump** — build fails with "AGP X requires Gradle Y+". Bump both.
- **JDK 11 in CI runner, JDK 17 expected** — set `JAVA_HOME` correctly or use `actions/setup-java@v4` with `java-version: '17'`.
- **Compose BOM and individual Compose artifacts pinned independently** — the BOM resolves Compose-Material3 / Compose-UI versions; don't pin those separately or you'll fight the BOM. Pin only the BOM in `[versions]`.
- **AGP 8.x release notes treated as the source of truth, but a third-party plugin is incompatible** — convention plugins that load AGP types (`com.android.build.gradle.LibraryExtension`) must compile against the same AGP version the project uses. If a `build-logic/convention` module fails to build, check its `compileOnly(libs.android.gradle.plugin)` version.

## A note on bleeding-edge

Tracking AGP / Kotlin / Compose beta or RC releases buys you new features but pays in cryptic errors. Production codebases should:

- Stick to stable AGP releases.
- Bump Kotlin only after the matching KSP + Compose Compiler pairing is stable.
- Test convention plugins (which compile against AGP types) on the new version *before* the rest of the team upgrades.

The cost of being one minor behind is usually small; the cost of being on a broken pre-release is days of debugging.
