# Library-Specific Keep Rules

Most major Android libraries that use reflection ship their own `consumer-rules.pro` — you don't write rules for them at the app level. But some patterns require app-level rules, either because the library doesn't ship rules or because you're using its features in a way the default rules don't cover.

This reference is for **app-level** rules. Library authors writing `consumer-rules.pro` see `consumer-rules.md`.

## Moshi (`@JsonClass`)

Modern Moshi (`moshi-kotlin-codegen` + KSP) generates adapters at compile time, so reflection isn't needed. If you use *runtime* reflection (`KotlinJsonAdapterFactory()`), rules are required.

**Codegen path (recommended):**

```kotlin
@JsonClass(generateAdapter = true)
data class User(val id: String, val name: String)
```

Moshi ships `consumer-rules.pro`. No app-level rules needed.

**Runtime reflection path:**

```kotlin
val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()
```

```proguard
# Keep @JsonClass-annotated data classes — fields are reflectively read
-keepclassmembers,allowobfuscation @com.squareup.moshi.JsonClass class * {
    <init>(...);
    <fields>;
}

# Or for classes annotated with @JsonClass but not using codegen:
-keep @com.squareup.moshi.JsonClass class * { <init>(...); }
```

## Room (`@Entity`, `@Dao`, `@Database`)

Room ships its own `consumer-rules.pro`. Add app-level rules only if you're using `RoomMasterTable` reflection or custom type converters that R8 can't trace.

For `@TypeConverter` methods on a class that R8 might shrink:

```proguard
-keep class com.kozinga.db.Converters {
    @androidx.room.TypeConverter <methods>;
}
```

For databases used via `DatabaseUtils` reflection (unusual):

```proguard
-keep class * extends androidx.room.RoomDatabase
```

## Retrofit

Retrofit ships extensive rules. Most apps don't need any app-level Retrofit rules. Exceptions:

- **Custom converter factories** that reflect on user types:

  ```proguard
  -keepattributes Signature, InnerClasses, EnclosingMethod
  -keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
  ```

  These attributes are already kept by Retrofit's bundled rules, but worth adding to your own `proguard-rules.pro` for clarity if you write a custom converter.

- **Interface response types** in modules that don't have their own `consumer-rules.pro`:

  ```proguard
  -keep class com.kozinga.api.response.** { *; }
  ```

  Better: convert response types to `@JsonClass(generateAdapter = true)` data classes (Moshi codegen path) and avoid needing this rule.

## Hilt (Dagger)

Hilt ships `consumer-rules.pro`. App-level rules are almost never needed. Exception: if you use `EntryPointAccessors.fromApplication(...)` patterns with custom entry points, R8 may not trace the reflection.

Generally trust Hilt's bundled rules.

## Glide

```proguard
# If you use Glide's reflection-based module discovery:
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep public class * extends com.bumptech.glide.module.AppGlideModule
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** { **[] $VALUES; public *; }
```

Glide ships these in its `consumer-rules.pro`. Add to your `proguard-rules.pro` only if you have custom `@GlideModule`-annotated classes in your app.

## kotlinx.serialization

```proguard
# Keep generated serializers (named like com.example.Foo$Companion serializer)
-keepclasseswithmembers class **.*$Companion {
    kotlinx.serialization.KSerializer serializer(...);
}

# Keep classes annotated @Serializable (their fields are reflected at runtime)
-keep,allowobfuscation @kotlinx.serialization.Serializable class * { *; }

# Keep companion object instances for sealed classes
-keepclasseswithmembers class * {
    @kotlinx.serialization.Serializable <fields>;
}
```

kotlinx.serialization's bundled rules are minimal — these are often app-level additions.

## Gson (legacy projects)

```proguard
# Generic types are reflected
-keepattributes Signature, *Annotation*

# Keep classes used as Gson type references
-keep class com.kozinga.api.legacy.** { *; }

# Keep no-arg constructors (Gson reflectively instantiates)
-keepclassmembers class com.kozinga.api.legacy.** {
    <init>();
}
```

Gson has been replaced by Moshi or kotlinx.serialization in most new code. Don't add Gson to new modules.

## OkHttp / Okio

OkHttp ships `consumer-rules.pro`. The common pattern is `-dontwarn` for optional crypto deps:

```proguard
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
```

These are usually already in your project (OkHttp's rules add them automatically). No app-level addition typically needed.

## Parcelable

Custom Parcelable classes need their `CREATOR` field kept:

```proguard
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}
```

This is in `proguard-android-optimize.txt` by default. No app rule needed unless you've replaced the default ProGuard file (which you shouldn't).

For `@Parcelize` (the Kotlin annotation), no rule needed — the codegen produces standard Parcelable classes covered by the above.

## WebView JavaScript bridge

If you expose Java/Kotlin methods to JavaScript via `WebView.addJavascriptInterface(...)`:

```proguard
# WebView's JS bridge reflects on @JavascriptInterface-annotated methods
-keepclassmembers class com.kozinga.webview.JsBridge {
    @android.webkit.JavascriptInterface <methods>;
}
```

If the class is also reflected, keep the class itself:

```proguard
-keep class com.kozinga.webview.JsBridge { *; }
```

## Native methods (JNI)

```proguard
# Standard rule in proguard-android-optimize.txt — keeps native method names
-keepclasseswithmembernames class * {
    native <methods>;
}
```

This is included by default. If you've added classes that *call into* native code and rely on method names being un-obfuscated, you may need narrower rules.

## Reflection via `Class.forName`

```kotlin
val clazz = Class.forName("com.kozinga.feature.HiddenScreen")
```

R8 can't statically detect that `HiddenScreen` is reflected — the class name is a string.

```proguard
-keep class com.kozinga.feature.HiddenScreen
```

**Better: refactor to avoid `Class.forName`.** Use a sealed-class factory, a Hilt-injected registry, or anything else that's traceable. Reflection-by-name is an anti-pattern for shrinkable codebases.

## Enums used with `valueOf`

```kotlin
val side = Side.valueOf(string)
```

Enum `valueOf` is reflected. R8 usually traces this, but for safety:

```proguard
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
```

This is in `proguard-android-optimize.txt` by default.

## Compose

Compose generally doesn't need app-level keep rules — the Compose Compiler plugin generates code with proper visibility. Exception: `@Preview` Composables that you want stripped from release:

```proguard
# Preview functions are debug-only; let R8 remove them in release
-assumenosideeffects class androidx.compose.ui.tooling.preview.Preview {
    *;
}
```

(`-assumenosideeffects` is an optimization hint, not a keep rule — it tells R8 it's safe to remove calls.)

## Common pitfalls

- **Copy-pasted rules from Stack Overflow** that target outdated library versions — Moshi's old reflection-based rules don't match the new codegen path. Audit before pasting.
- **Library rules in `consumer-rules.pro` AND in app-level `proguard-rules.pro`** — duplicates. Trust the library; remove the app-level copy.
- **`-keep class **` patterns** — defeat shrinking. Always narrow.
- **Forgetting `-keepattributes` for reflection-using libraries** — `Signature`, `InnerClasses`, `EnclosingMethod`, `*Annotation*` are commonly required. Most library `consumer-rules.pro` include them, but custom reflection might not.
- **No release build testing** — rules look fine, build passes, app crashes in production with `ClassNotFoundException`. Always test minified release builds.
- **Adding rules speculatively** — "just in case" rules accumulate. Each one blocks R8 work. Add only when you've reproduced a release-build crash that the rule fixes.
