# Common R8 / Release-Build Crashes

A diagnostic guide for the most common failures in `minifyEnabled = true` builds. Each pattern has a signature, a root cause, and the typical fix.

## `ClassNotFoundException`

**Pattern:**

```
java.lang.ClassNotFoundException: Didn't find class "com.kozinga.feature.home.HomeViewModel"
    on path: DexPathList[[zip file "/data/app/com.kozinga.app/base.apk"]]
```

**Root cause:** R8 stripped a class that runtime code reflectively references — typically via `Class.forName(...)`, library reflection (Moshi, Gson, Retrofit), or `addJavascriptInterface(...)`.

**Diagnosis:**

1. Find the call site that references this class. Search for `"HomeViewModel"` (string literal) or `Class.forName(`.
2. If it's library reflection, check the library's `consumer-rules.pro`. If incomplete, add app-level rules.
3. If it's your own `Class.forName`, refactor to avoid reflection (preferred) or add `-keep class com.kozinga.feature.home.HomeViewModel`.

## `NoSuchMethodException`

**Pattern:**

```
java.lang.NoSuchMethodException: com.kozinga.api.User.<init> []
```

**Root cause:** A reflection-using library (Moshi, Room, Gson) tried to instantiate a class via its no-arg constructor, but R8 stripped that constructor because no compiled code calls it.

**Diagnosis:**

```proguard
# Add the no-arg constructor back:
-keepclassmembers class com.kozinga.api.User {
    <init>(...);   # all constructors
    # Or specifically:
    <init>();      # just the no-arg
}
```

For Moshi specifically: better fix is to migrate to `@JsonClass(generateAdapter = true)` + KSP, which generates code that doesn't need reflective construction.

## `NoSuchFieldException`

**Pattern:**

```
java.lang.NoSuchFieldException: name
    at java.lang.Class.getDeclaredField(Class.java)
```

**Root cause:** R8 obfuscated or removed a field that reflection accesses by name.

**Diagnosis:**

```proguard
# Keep the field by name:
-keepclassmembers class com.kozinga.api.User {
    java.lang.String name;
}

# Or for all fields of a class:
-keepclassmembers class com.kozinga.api.User {
    <fields>;
}
```

For `@Json("name")` Moshi annotations, this is solved by:

```proguard
-keepclassmembers class * {
    @com.squareup.moshi.Json *;
}
```

## `InvocationTargetException` wrapping a `NullPointerException`

**Pattern:**

```
java.lang.reflect.InvocationTargetException
    at java.lang.reflect.Method.invoke(Method.java)
    ...
Caused by: java.lang.NullPointerException
    at com.kozinga.api.User.<init>(SourceFile:42)
```

**Root cause:** Reflection reached the method but a field that should have been initialized is null. Typical cause: R8 stripped a setter or auto-generated initializer.

**Diagnosis:** Look at the line in the obfuscated source (deobfuscate via `mapping.txt`). If the line is inside a generated initializer, the keep rule for the class wasn't broad enough.

Often the fix is:

```proguard
# Keep both constructor AND all fields:
-keepclassmembers class com.kozinga.api.User {
    <init>(...);
    <fields>;
}
```

## `KotlinClassNotFoundException`

**Pattern:**

```
kotlin.reflect.jvm.internal.KotlinReflectionInternalError:
    Could not find class metadata for class com.kozinga.feature.foo.MyClass
```

**Root cause:** R8 stripped Kotlin metadata annotations (`@kotlin.Metadata`) that Kotlin reflection requires.

**Diagnosis:** Modern R8 in full mode handles Kotlin metadata correctly by default. Legacy projects may need:

```proguard
-keep class kotlin.Metadata { *; }
```

Better: use compile-time codegen (KSP for Moshi/Room, kotlinx-serialization) so runtime reflection isn't needed.

## `UnsatisfiedLinkError`

**Pattern:**

```
java.lang.UnsatisfiedLinkError: No implementation found for void com.kozinga.native.NativeBridge.processFrame()
    (tried Java_com_kozinga_native_NativeBridge_processFrame and ...)
```

**Root cause:** JNI method names were obfuscated, so the native library can't find them by name.

**Diagnosis:**

```proguard
# Standard JNI rule (in proguard-android-optimize.txt):
-keepclasseswithmembernames class * {
    native <methods>;
}
```

If you also need the *class* to be findable by JNI:

```proguard
-keep class com.kozinga.native.NativeBridge {
    native <methods>;
}
```

## `ClassCastException` in a Parcelable

**Pattern:**

```
java.lang.ClassCastException: Parcelable Creator a.b.c not compatible with com.kozinga.models.MyParcelable
```

**Root cause:** R8 obfuscated the `CREATOR` field's containing class or its type.

**Diagnosis:**

```proguard
# Standard rule (in proguard-android-optimize.txt):
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}
```

Should be there by default. If you're using `@Parcelize` (Kotlin), no additional rules needed.

## XML inflation crashes

**Pattern:**

```
android.view.InflateException: Binary XML file line #X:
    Error inflating class com.kozinga.widget.CustomView
```

**Root cause:** R8 obfuscated a custom View class that XML inflation looks up by name.

**Diagnosis:**

```proguard
# Keep custom Views and their inflation constructors:
-keep public class * extends android.view.View {
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
}
```

Standard in `proguard-android-optimize.txt`. If you've replaced that file with a hand-rolled set, you need to re-add.

## `NoClassDefFoundError`

**Pattern:**

```
java.lang.NoClassDefFoundError: Failed resolution of: Lcom/kozinga/SomeClass;
```

**Root cause:** R8 stripped a class that's referenced but no longer exists. Often happens with optional/conditional dependencies.

**Diagnosis:**

- If the class is in a library that's only used under certain conditions (e.g., debug-only logging), exclude it from release builds via `debugImplementation(...)` instead of `implementation(...)`.
- If it's a class that *is* used in release but R8 didn't trace the use, add `-keep`.
- If it's a *missing* dependency (you removed a library but a transitive reference remains), audit your `dependencies {}` block.

## `IllegalStateException: Hilt @ApplicationContext or @ActivityContext was not properly bound`

**Pattern:** Hilt-injected `@ApplicationContext` fails to resolve in release.

**Root cause:** R8 stripped the generated Hilt entry-point class. Usually because the `@AndroidEntryPoint`-annotated class is itself reflected.

**Diagnosis:** Hilt ships `consumer-rules.pro` that should handle this. If it doesn't:

```proguard
-keep @dagger.hilt.android.AndroidEntryPoint class *
-keep @dagger.hilt.InstallIn class *
-keep @dagger.hilt.android.qualifiers.ApplicationContext class *
```

Verify your Hilt version is current; older versions had less complete consumer rules.

## Resource not found at runtime

**Pattern:**

```
android.content.res.Resources$NotFoundException: String resource ID #0x7f0e0042
```

**Root cause:** `isShrinkResources = true` stripped a string that's looked up by name via `getIdentifier(...)`.

**Diagnosis:**

```xml
<!-- res/raw/keep.xml -->
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@string/dynamic_*" />
```

R8 can't trace `getIdentifier(...)` lookups. Tell the resource shrinker explicitly which resources to keep.

## Debugging workflow

When a release-only crash hits, here's the workflow:

1. **Reproduce with `isMinifyEnabled = true`** — confirm it's R8-related (not a real bug).
2. **Get the obfuscated stack trace** from the crash reporter.
3. **Deobfuscate via mapping.txt** (see `mapping-files.md`).
4. **Identify the class/method that was stripped** — usually obvious from the exception type.
5. **Find the reflection site** — what library/code accessed the stripped symbol?
6. **Add the narrowest keep rule possible** to address it.
7. **Test the release build again** — confirm fix.
8. **Audit similar patterns** — if Moshi crashed on one DTO, you may have other unprotected DTOs.

## Preventing release-only crashes

- **Enable `isMinifyEnabled = true` in a staging variant** that mirrors release and run integration / UI tests against it pre-release.
- **Audit `proguard-rules.pro`** when adding any reflection-using library — check the library's docs for required rules.
- **Test deeply-linked / less-frequented screens** in minified builds — they're where reflection issues often hide.
- **Use codegen over runtime reflection** wherever possible — Moshi codegen, Room (always codegen), Retrofit (no reflection needed if response types are codegen'd).

## Common pitfalls

- **Fix is `-keep class com.kozinga.**` to make the crash go away** — instead of finding the root cause. Now you're shipping a less-shrunk APK forever. Track down the specific class.
- **Disabling minification entirely** — same problem, larger APK, slower app. Always solve the rule.
- **Adding `-dontoptimize`** to fix an optimization-related crash — masks the real issue and disables all optimization. Find the narrower rule.
- **Re-using rules from old Android tutorials** — outdated patterns (`-keep class * extends Serializable`) carry over and bloat APK. Audit periodically.
- **Mapping.txt lost** — crash report is unreadable, can't even diagnose. See `mapping-files.md` for retention.
- **R8 succeeds, build passes, app crashes in production** — only because release builds weren't tested. Test minified builds before every release.
