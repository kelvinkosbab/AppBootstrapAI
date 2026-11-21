---
description: Authoring Android and Kotlin library modules that apps consume — explicit API mode, an ABI dump checked in CI, Java-friendly binary-stable API, consumer R8 rules instead of self-minifying, resource prefixes, a conservative Kotlin and SDK floor, and signed Maven Central publishing
globs: "**/*.{kt,kts},**/consumer-rules.pro,**/gradle.properties"
paths:
  - "**/*.{kt,kts}"
  - "**/consumer-rules.pro"
  - "**/gradle.properties"
must:
  - "Turn on `explicitApi()` in every published library module."
  - "Commit an ABI dump and fail CI on unreviewed ABI changes (binary-compatibility-validator or KGP abiValidation)."
  - "No public data classes or new default parameters without `@JvmOverloads`; both break binary compatibility."
  - "Libraries don't minify themselves; reflection keeps ship in `consumer-rules.pro`."
  - "Publish signed artifacts with sources, KDoc, and a complete POM to the Central Portal; never from a laptop."
---

# Android Library Authoring

For repos whose product is an Android or Kotlin library (AAR or JAR) that apps depend on. An app can change any internal detail at will; a library's public API, binary layout, and transitive dependencies ship into apps you don't control. The `android-library-pro` skill covers each section in depth; build-script mechanics stay in `android-gradle-conventions.md` and R8 details in `r8-shrink-pro`.

## Module setup

- **`com.android.library`** with a `namespace`, no `applicationId`, and no `targetSdk` (deprecated for libraries; set `lint.targetSdk` / `testOptions.targetSdk` instead). `minSdk` as low as the code really supports.
- **`resourcePrefix = "mylib_"`** and every resource named with it. Non-transitive R classes stay on.
- **`aarMetadata { minCompileSdk = … }`** when consumers need a newer `compileSdk` than they'd assume.
- **`implementation` by default, `api` only for types in your public signatures.** Each `api` dependency is a version you force on every consumer.
- **Kotlin floor for consumers**: set `compilerOptions.apiVersion` / `languageVersion` and `coreLibrariesVersion` to the oldest Kotlin you support, so building with a new compiler doesn't force consumers to upgrade.
- **Pure-Kotlin code with no Android APIs goes in a JVM (or Multiplatform) module**, not an AAR.

## Public API

- **`kotlin { explicitApi() }`** in every published module: every public declaration states its visibility and return type.
- **`internal` by default.** `@PublishedApi internal` only for what public inline functions need. Experimental API behind a `@RequiresOptIn` annotation.
- **Binary compatibility, not just source**: don't add a default parameter to a public function without `@JvmOverloads` (or a new overload), don't expose `data class` publicly (`copy` and `componentN` freeze the constructor), and remember adding a subclass to a public `sealed` type or an entry to a public `enum` breaks consumers' `when`.
- **Java callers are customers**: `@JvmStatic` on companion factories, `@JvmName` for clashing names, `@Throws` on functions Java must catch, no `internal` names leaking through mangling.
- **Compose libraries**: stable parameter types, `modifier: Modifier = Modifier` as the first optional parameter, slot APIs, no `ViewModel` or `Context` dependencies in components.

## Compatibility checks

- **Commit an ABI dump and check it in CI**: the `org.jetbrains.kotlinx.binary-compatibility-validator` plugin (`apiDump` / `apiCheck`, files in `api/`) or the Kotlin Gradle plugin's built-in `abiValidation`. A dump diff is reviewed in the PR like code.
- **SemVer**: an ABI removal or change is MAJOR, an addition MINOR. Deprecate with `ReplaceWith` and escalate `WARNING` → `ERROR` → `HIDDEN` across releases before removing.
- **`CHANGELOG.md` entry for every public change**, under Keep a Changelog headings.

## Shrinking and resources

- **Don't minify the library** (`isMinifyEnabled = false` on release): the app's R8 shrinks it.
- **Ship `consumer-rules.pro`** via `consumerProguardFiles` with only the keeps your reflection needs. No global options (`-dontobfuscate`, `-dontoptimize`, `-allowaccessmodification`); they apply to every consumer.
- **Custom lint checks ship with the AAR** through `lintPublish`.

## Publishing

- **Maven Central through the Central Portal** (OSSRH is retired) with a verified namespace, or a private repository for internal libraries. Not JitPack for anything consumers depend on in production.
- **Signed artifacts** (in-memory GPG key from CI secrets) with a sources jar, a KDoc/Javadoc jar from Dokka, Gradle Module Metadata, and a POM with name, description, URL, license, developers, and SCM.
- **Releases come from CI on a tag**, with the version from the tag, never from a developer's machine.
- **Multi-artifact libraries publish a BOM** (`java-platform`) so consumers align versions.

## Quality bar

- **A sample app module** that uses only the public API and builds in CI.
- **Tests through the public API**, shared fakes in `testFixtures` or a `-testing` artifact consumers can use too.
- **Dokka docs for every public symbol**, published with each release.
