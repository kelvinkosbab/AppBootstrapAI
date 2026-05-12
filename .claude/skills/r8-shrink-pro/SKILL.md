---
name: r8-shrink-pro
description: Reviews Android R8 / ProGuard configuration for code-shrinking, optimization, and obfuscation. Covers `-keep` rule discipline, library `consumer-rules.pro` discipline, common reflection-using library rules (Moshi, Room, Hilt, Retrofit, Glide), mapping-file workflow, debugging release-build crashes. Use when reading, writing, or reviewing ProGuard/R8 configuration files.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "Android Developers — Shrink, obfuscate, and optimize your app (https://developer.android.com/build/shrink-code), Android Developers — R8 docs"
---

Review Android R8 / ProGuard configuration for correctness, minimal-keep discipline, and release-build resilience. R8 is the default code shrinker in AGP 8.x — it's ProGuard-compatible (same `-keep` rule syntax) but with better optimization and bundled obfuscation. Report only genuine problems; don't add `-keep` rules speculatively.

Review process:

1. Frame what R8 is doing using `references/fundamentals.md` — shrinking, optimizing, obfuscating, repackaging; what `minifyEnabled = true` actually triggers.
2. Validate `-keep` rule discipline using `references/keep-rules.md` — when to use `-keep` vs `-keepclassmembers` vs `-keepnames`, and why blanket `-keep` is wrong.
3. For library modules, check `consumer-rules.pro` using `references/consumer-rules.md` — what libraries owe their consumers.
4. Check common reflection-library rules using `references/library-keep-rules.md` — Moshi, Room, Retrofit, Hilt, Glide, kotlinx-serialization.
5. Validate mapping-file workflow using `references/mapping-files.md` — keeping `mapping.txt`, deobfuscating stack traces, Crashlytics integration.
6. Diagnose release-build crashes using `references/common-crashes.md` — `ClassNotFoundException`, `NoSuchMethodException`, native-library symbol mismatches.

If doing a partial review, load only the relevant reference files.

## Core Instructions

- **R8 is default in AGP 3.4+.** The `proguardFiles` directive uses ProGuard rule syntax; R8 interprets them. There's no separate "use R8" flag — `minifyEnabled = true` turns it on.
- **Default to `proguard-android-optimize.txt` + your `proguard-rules.pro`.** AGP ships sensible defaults via `getDefaultProguardFile("proguard-android-optimize.txt")`.
- **Library modules use `consumer-rules.pro`**, not `proguardFiles`. Rules in `consumer-rules.pro` are inherited by every consumer that depends on the library. See `consumer-rules.md`.
- **`-keep` is the heavy hammer** — it prevents shrinking, optimization, AND obfuscation for the matched class. Prefer narrower forms (`-keepclassmembers`, `-keepnames`) when only one of those is needed.
- **Reflection-using libraries (Moshi, Room, Retrofit, Hilt, Glide, kotlinx-serialization) need keep rules.** Most ship their own `consumer-rules.pro`, but some (or custom uses) require app-level additions.
- **Always test release builds** with `minifyEnabled = true` *before* shipping. Many R8 crashes only surface in release.
- **Keep the `mapping.txt`** from every release. Without it, post-release crash reports are unreadable obfuscated stack traces.

## Output Format

For ProGuard/R8 reviews, organize findings by file. For each:

1. State the file (`proguard-rules.pro`, `consumer-rules.pro`, etc.) and line.
2. Name the rule issue.
3. Show before/after.

Skip files with no issues. End with a prioritized summary.

Example output:

### proguard-rules.pro

**Line 8: `-keep class com.kozinga.** { *; }` is too broad — defeats shrinking for the entire app code.**

```proguard
# Before
-keep class com.kozinga.** { *; }

# After — keep only what reflection actually touches:
-keep @com.squareup.moshi.JsonClass class * { <fields>; }
-keepclassmembers class com.kozinga.models.** {
    @com.squareup.moshi.Json *;
}
```

**Line 18: `-keepnames` on a class that's reflectively constructed — should be `-keep`.**

```proguard
# Before — preserves the name but allows R8 to remove the class:
-keepnames class com.kozinga.WebViewBridge

# After — preserves the class itself:
-keep class com.kozinga.WebViewBridge { *; }
```

### consumer-rules.pro (missing for :core:network)

**Library `:core:network` exposes Retrofit interfaces but doesn't ship `consumer-rules.pro` — consumers' R8 strips method signatures that Retrofit needs at runtime.**

```proguard
# consumer-rules.pro for :core:network
-keep,allowobfuscation,allowshrinking interface retrofit2.Call
-keep,allowobfuscation,allowshrinking class kotlin.coroutines.Continuation
-keepattributes Signature, InnerClasses, EnclosingMethod
```

### Summary

1. **Over-broad keep (high):** `com.kozinga.**` blanket keep defeats shrinking for the entire app.
2. **Missing consumer-rules.pro (high):** Library `:core:network` doesn't ship Retrofit-required rules.
3. **Wrong keep variant (low):** `-keepnames` where `-keep` is needed.

End of example.

## References

- `references/fundamentals.md` — what R8 does (shrink / optimize / obfuscate / repackage), how it differs from old ProGuard, full-mode vs compatibility-mode, what `minifyEnabled` triggers, `shrinkResources` for resources.
- `references/keep-rules.md` — `-keep`, `-keepclassmembers`, `-keepclasseswithmembers`, `-keepnames`, `-keepattributes`. Class-spec syntax (`@Annotation class * { <fields>; }`). The hierarchy from most-specific to least-specific.
- `references/consumer-rules.md` — `consumer-rules.pro` contract with library consumers. When to use it vs in-tree `proguard-rules.pro`. Library authors' responsibility for shipping correct rules.
- `references/library-keep-rules.md` — concrete rules for Moshi (`@JsonClass`), Room (`@Entity`/`@Dao`), Retrofit (annotation-driven methods), Hilt (generated classes), Glide (modules), kotlinx-serialization (annotated classes), reflection-via-`Class.forName`.
- `references/mapping-files.md` — `mapping.txt` retention, deobfuscating release stack traces (`retrace`), Crashlytics mapping upload, R8 missing-rules report (`-printusage`, `-printseeds`, `-printmapping`).
- `references/common-crashes.md` — `ClassNotFoundException`, `NoSuchMethodException`, `InvocationTargetException` from missing reflection rules, native-library symbol mismatches (`UnsatisfiedLinkError`), Kotlin metadata stripping (`KotlinClassNotFoundException`).
