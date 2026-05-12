# `consumer-rules.pro`: Library Authors' Contract

Library modules don't run R8 themselves — but their *consumers* do. A library that uses reflection (Moshi adapters, Room schemas, Retrofit annotated interfaces, anything reading types via `Class.forName`) must ship a `consumer-rules.pro` so consumer apps' R8 doesn't strip away the runtime-reflected bits.

This is the contract:

- **Library author:** ships `consumer-rules.pro` with every reflection-required keep rule.
- **Consumer app:** R8 automatically merges in every transitive `consumer-rules.pro`. The consumer doesn't write app-level rules to "use" a library.

## Where it lives

```kotlin
// :core/network/build.gradle.kts (library module)
plugins {
    alias(libs.plugins.android.library)
}

android {
    defaultConfig {
        consumerProguardFiles("consumer-rules.pro")
    }
}
```

```
core/network/
├── build.gradle.kts
├── consumer-rules.pro      # ← lives in the module root
└── src/main/kotlin/...
```

The file name is conventional but not magic — set it explicitly via `consumerProguardFiles(...)`.

## `consumer-rules.pro` vs `proguardFiles`

| Directive | Applies to... | When the app is built... |
|-----------|---------------|---------------------------|
| `consumerProguardFiles("consumer-rules.pro")` | The library's transitive consumers | Rules are inherited by every app that uses this library |
| `proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")` | Only this module when it minifies itself | Rules apply only when this module is the entry point (rare for libraries) |

**Library authors:**

- Always: `consumerProguardFiles("consumer-rules.pro")` if your library uses reflection.
- Rarely: `proguardFiles(...)` — only if the library has its own minified output (e.g., a published AAR).

## What goes in `consumer-rules.pro`

Only what the *library* needs. Not what the library's transitive dependencies need (those ship their own `consumer-rules.pro`).

**Pattern: rules for the library's public reflection surface.**

For a Retrofit interface library:

```proguard
# consumer-rules.pro for a library that ships Retrofit interfaces

# Retrofit's reflection needs annotation metadata on interface methods.
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations

# Keep the interfaces themselves (so consumers can reference them via Retrofit.create()):
-keep,allowobfuscation,allowshrinking interface com.kozinga.network.api.*Service

# Keep methods with Retrofit annotations:
-keepclassmembers,allowshrinking,allowobfuscation interface com.kozinga.network.api.* {
    @retrofit2.http.* <methods>;
}

# Keep return types referenced by those methods (Retrofit reflects on them):
# (If your return types are in a separate :core:models module, they ship their own rules.)
```

For a library that exposes Moshi-annotated classes to consumers:

```proguard
# consumer-rules.pro for a library that exposes Moshi-annotated DTOs

-keep,allowobfuscation,allowshrinking @com.squareup.moshi.JsonClass class *
-keepclassmembers,allowobfuscation,allowshrinking class com.kozinga.api.dto.** {
    @com.squareup.moshi.Json *;
}
```

For a library with a custom annotation processor that consumers' R8 should respect:

```proguard
-keep,allowshrinking @com.kozinga.api.MyCustomAnnotation class *
```

## What does NOT go in `consumer-rules.pro`

- **Rules for the library's transitive dependencies.** If you use Retrofit, Retrofit ships its own `consumer-rules.pro`. You don't ship those rules; that creates merge surprises if Retrofit updates theirs.
- **Rules for app-specific reflection.** Only the public API surface of *this* library.
- **`-dontoptimize`, `-dontobfuscate`, `-dontshrink`** — these are global flags. Libraries should never tell consumers to disable optimization. If you think you need this, you have the wrong rule.
- **`-printusage`, `-printmapping`** — debug-output rules. Consumer-level concerns, not library-level.

## Testing `consumer-rules.pro`

A library author can validate their consumer rules by:

1. **Building a sample app** that depends on the library with `isMinifyEnabled = true`.
2. **Exercising the public reflection surface** (deserialize a Moshi class, call a Retrofit endpoint, etc.).
3. **Watching for runtime crashes** — `ClassNotFoundException` / `NoSuchMethodException` in release mode.

If you can't ship a sample app, at minimum: build the library, add it as a dep in a test app, enable R8 in release, hit the API. Found rules by failure is the standard workflow.

## Common library rule recipes

### Moshi adapter library

```proguard
-keep,allowobfuscation,allowshrinking @com.squareup.moshi.JsonClass class *
-keepclassmembers,allowobfuscation,allowshrinking class com.kozinga.lib.** {
    @com.squareup.moshi.Json *;
    <init>(...);   # constructors are needed for Moshi's reflective construction
}
```

### Room database library

```proguard
-keep class com.kozinga.lib.database.** { *; }   # Room generates code referencing these
-keep @androidx.room.Entity class *
-keep @androidx.room.Dao class *
```

(Room ships extensive `consumer-rules.pro` itself. App-level rules for Room are rarely needed.)

### Custom annotation processor

```proguard
-keep @com.kozinga.lib.MyAnnotation class *
-keepclassmembers class * {
    @com.kozinga.lib.MyAnnotation <methods>;
    @com.kozinga.lib.MyAnnotation <fields>;
}
```

### Library exposing a custom View

```proguard
-keep public class com.kozinga.lib.widget.* extends android.view.View {
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
}
```

## Migration: from `proguard-rules.pro` in a library to `consumer-rules.pro`

A common legacy pattern: the library has `proguard-rules.pro` and `proguardFiles(...)` in its `build.gradle.kts`. This *doesn't propagate to consumers* — those rules only apply when the library minifies itself, which is almost never.

**Migration:**

1. Rename `proguard-rules.pro` → `consumer-rules.pro` (or add a new file).
2. Replace `proguardFiles(...)` with `consumerProguardFiles("consumer-rules.pro")` in the library's `build.gradle.kts`.
3. Test by building a consumer with `isMinifyEnabled = true`.

## Common pitfalls

- **Library has `proguardFiles(...)` instead of `consumerProguardFiles(...)`** — rules are dead. Consumers don't get them.
- **`consumer-rules.pro` includes rules for transitive deps** — duplicates upstream rules. When upstream changes, your rules drift.
- **`-keep class com.kozinga.lib.** { *; }`** in a library — defeats consumers' shrinking of your library entirely. Audit and narrow.
- **`-dontoptimize` / `-dontobfuscate`** in `consumer-rules.pro` — sabotages consumers' apps globally. Never use these in library rules.
- **Test only the library in isolation** — `:lib` builds fine, fails when consumed because the library's reflection paths weren't exercised. Always test with a real consumer app.
- **Forgetting to bump `consumerProguardFiles` when adding a new reflection-using API** — release builds of consumer apps crash. Library maintainers should test minified release builds of a sample app on every release.
- **Multiple `consumer-rules.pro` files merged across library modules** — duplicate rules are fine; conflicting rules (e.g., `-keep` vs `-keepnames` on the same class) take the more-permissive one (`-keep` wins). Generally not a problem but worth knowing during debugging.
