# Kotlin Library API and ABI

A Kotlin library has two contracts:

- **Source compatibility**: consumers' code compiles against the new version.
- **Binary compatibility (ABI)**: code compiled against the old version runs against the new one. This matters for every JVM library, because an app often gets your newer version transitively through another library that was compiled against the older one. A binary break shows up as `NoSuchMethodError` or `AbstractMethodError` at runtime in the app, not at compile time.

## Explicit API mode

```kotlin
kotlin { explicitApi() }
```

Every declaration that would be public by default must say `public` (or narrower) and declare its return type. This stops accidental public API (Kotlin's default visibility is public) and inferred return types that change when the implementation does. Use `explicitApiWarning()` only while migrating.

## Visibility

- `internal` by default. Internal declarations are compiled as public JVM members with mangled names, so Java callers can still reach them; never rely on `internal` for security.
- `@PublishedApi internal` for internal declarations a `public inline` function calls. They become ABI: the inlined call lives in the consumer's bytecode.
- Public inline functions are permanent: their bodies are copied into consumers. Fix a bug in one and old consumer binaries keep the old body.

## What breaks consumers

| Change | Source | Binary | Bump |
|---|---|---|---|
| Add public class / function / property | ok | ok | MINOR |
| Add a parameter with a default value | ok | **breaks** (JVM signature changes) | MAJOR, or add an overload instead |
| Add parameter with default + `@JvmOverloads` from the start | ok | ok for the overloads generated | MINOR |
| Remove / rename public declaration | breaks | breaks | MAJOR (deprecate first) |
| Change parameter or return type (including nullability `T` → `T?` on return) | breaks | breaks | MAJOR |
| Make a function `suspend` or remove `suspend` | breaks | breaks | MAJOR |
| Add an abstract member to an interface or abstract class | breaks implementors | `AbstractMethodError` | MAJOR; add with a default body instead |
| Add a property to a public `data class` constructor | breaks `componentN` / `copy` callers | breaks | MAJOR |
| Add a subclass to a public `sealed` class / interface | breaks exhaustive `when` | ok | MAJOR unless documented non-exhaustive |
| Add an enum entry | breaks exhaustive `when` | ok | MAJOR unless documented non-exhaustive |
| Move a top-level function to another file | ok | **breaks** (`FileNameKt` class changes) | MAJOR, or pin with `@file:JvmName` |
| `open` → final, or change class kind | breaks | breaks | MAJOR |
| Raise `minSdk`, Kotlin `apiVersion`, `minCompileSdk`, or Java target | breaks consumers below | n/a | MAJOR (MINOR if your policy says so, documented) |
| Add `@RequiresOptIn` annotation to existing API | breaks (opt-in error) | ok | MAJOR |

### Data classes

`data class` generates `copy(...)` and `componentN()` from the constructor, so adding, removing, or reordering a property is a binary and source break. For public API:

- Use a regular class with `equals` / `hashCode` / `toString` written out (or Poko's `@Poko`), and a builder or factory function for construction.
- Or keep the `data class` but make the constructor `internal` / `private` and expose a factory, accepting that `copy` is still public (Kotlin 2.0.20+ warns about this mismatch; `@ConsistentCopyVisibility` makes `copy` match the constructor).

### Default parameters and Java

- `@JvmOverloads` on public functions and constructors with defaults generates the Java-callable overloads. Add it on day one: adding it later is fine, but adding a defaulted parameter to a function without it removes the old JVM signature.
- To add a parameter safely: add a new overload and keep the old one delegating to it, or add the parameter at the end of a function already annotated `@JvmOverloads`.

### Other Java interop

- `@JvmStatic` on companion-object factories and constants that Java should call as statics; `const val` for compile-time constants.
- `@JvmName` to give a Java-friendly name, or to avoid platform-declaration clashes (two functions with the same erasure).
- `@file:JvmName("Widgets")` on files with top-level public functions so the facade class name is stable and readable.
- `@Throws(IOException::class)` on functions Java callers must be able to catch checked exceptions from.
- `@JvmField` for public constants objects rather than getters only when the field will never need logic.
- Nullability annotations: Kotlin types already emit `@NotNull` / `@Nullable`; keep Java sources annotated (`androidx.annotation` or JSpecify) so Kotlin consumers don't see platform types.
- Function types: Java sees `Function1<…>` and must return `Unit.INSTANCE`. Offer a `fun interface` for callbacks Java will implement.

## Experimental API

```kotlin
@RequiresOptIn(message = "This API is experimental and may change in any release.", level = RequiresOptIn.Level.WARNING)
@Retention(AnnotationRetention.BINARY)
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY)
public annotation class ExperimentalWidgetsApi

@ExperimentalWidgetsApi
public fun Modifier.shimmer(): Modifier = …
```

Experimental API is excluded from the compatibility promise; say so in the README, and exclude it from ABI checks (below) if it churns.

## ABI dumps

Commit a text dump of the public ABI and fail CI when the code and the dump disagree. A change to the dump then shows up in review as a diff anyone can read.

### binary-compatibility-validator (works for Android library modules today)

```kotlin
// root build.gradle.kts
plugins {
    alias(libs.plugins.kotlinx.binary.compatibility.validator) // org.jetbrains.kotlinx.binary-compatibility-validator
}

apiValidation {
    ignoredProjects += listOf("sample")
    nonPublicMarkers += listOf("com.example.widgets.ExperimentalWidgetsApi")
}
```

- `./gradlew apiDump` writes `<module>/api/<module>.api`; commit it.
- `./gradlew apiCheck` (also wired into `check`) fails when the code's ABI differs from the file.
- A PR that changes the `.api` file needs a reviewer to classify each line: added lines are MINOR, removed or changed lines are MAJOR.
- Klib (multiplatform) validation is opt-in: `apiValidation { klib { enabled = true } }`.

### KGP built-in ABI validation (the successor)

Recent Kotlin Gradle plugin versions ship ABI validation in KGP itself (`kotlin { abiValidation { … } }`), with `checkKotlinAbi` / `updateKotlinAbi` tasks (Kotlin 2.2 called them `checkLegacyAbi` / `updateLegacyAbi` and required `@OptIn(ExperimentalAbiValidation::class)`). It's the long-term replacement for the standalone plugin. Check the Kotlin docs for the version you build with, confirm it covers your targets (including Android), and migrate one module at a time, keeping the dump files reviewed the same way.

Either way:

- Run the check on every PR, not only before release.
- Compare the dump against the last release tag when preparing a release, so several MINOR-looking PRs that add up to a break are caught.
- Regenerating the dump to make CI pass, without review, defeats the purpose; treat the dump like a lockfile that needs a human approval.

## Deprecation

```kotlin
@Deprecated(
    message = "Use render(theme) instead.",
    replaceWith = ReplaceWith("render(theme = Theme.Default)", "com.example.widgets.Theme"),
    level = DeprecationLevel.WARNING,
)
public fun render(): Unit = render(theme = Theme.Default)
```

- Release N: `WARNING` with `ReplaceWith` so IDEs offer the fix.
- Release N+1 (MINOR is fine): `ERROR`. Old binaries still link; source no longer compiles.
- Next MAJOR: `HIDDEN` or removal. `HIDDEN` keeps binary compatibility while removing it from source, useful for one more cycle.
- Every step goes in CHANGELOG under **Deprecated** / **Removed**.
