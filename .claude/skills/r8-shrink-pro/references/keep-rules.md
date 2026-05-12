# `-keep` Rules: Syntax and Discipline

The `-keep` family is R8/ProGuard's tool for excepting things from shrinking, optimization, and/or obfuscation. There are several variants — picking the *narrowest* one that solves the problem is the discipline.

## The hierarchy

From most permissive (worst — blocks the most R8 work) to most restrictive (best — blocks the least):

| Rule | Prevents... | Use when... |
|------|-------------|-------------|
| `-keep class X { *; }` | shrinking + optimizing + obfuscating, for class AND members | Reflection touches both the class itself and its members |
| `-keep class X` | shrinking + obfuscating the class; members can be removed | Class is reflected by name but its members aren't |
| `-keepclassmembers class X { *; }` | shrinking + obfuscating *members*; class can be removed if otherwise unused | Reflection touches members but the class is already kept |
| `-keepclasseswithmembers class X { @Annotation *; }` | only keeps class + members IF the members exist | Annotation-driven processors |
| `-keepnames class X` | obfuscating the name; allows shrinking | Class is referenced by name in non-essential contexts (logs, debugging) |
| `-keepclassmembernames class X { *; }` | obfuscating member names; allows shrinking | Member names are reflected but classes aren't |

**The default is wrong almost every time.** Most projects have `-keep class com.foo.** { *; }` somewhere. That's the heavy hammer; it defeats shrinking for entire packages. Audit and narrow.

## Class-spec syntax

Class specs use a mini-language for matching classes and members:

```proguard
# Match every class in a package and subpackages:
-keep class com.kozinga.models.** { *; }
        # ^^^^^^^^^^^^^^^^^^^^^^^  package match
        # ^^                       ** = recursive, * = one segment

# Match classes that extend a specific superclass:
-keep public class * extends androidx.fragment.app.Fragment

# Match classes annotated with a specific annotation:
-keep @com.squareup.moshi.JsonClass class *

# Match interfaces:
-keep interface com.kozinga.events.Event

# Match by class name pattern:
-keep class **.R$* { *; }   # all inner R classes (R.string, R.id, etc.)
```

Member specs (inside `{ ... }`):

```proguard
-keep class com.example.Foo {
    public <init>(...);              # all public constructors
    public <init>(android.content.Context);  # specific constructor
    public static void main(java.lang.String[]);  # specific static method
    *;                                # everything (class + members)
    <fields>;                         # all fields
    <methods>;                        # all methods
    @com.example.Keep <fields>;       # fields annotated with @Keep
    @com.example.Keep <methods>;      # methods annotated with @Keep
    public !static <methods>;         # public non-static methods
}
```

The negation operators (`!`) and access modifiers (`public`, `protected`, etc.) make rules quite expressive — exploit this to write narrower rules.

## `-keepattributes`

R8 strips JVM attributes by default. Some libraries need specific attributes to survive:

```proguard
-keepattributes Signature              # generic types — required by Retrofit, Moshi
-keepattributes Exceptions             # checked exceptions (Java interop)
-keepattributes *Annotation*           # all annotations — many libraries reflect them
-keepattributes EnclosingMethod        # for nested classes — required by some reflection
-keepattributes InnerClasses           # similar
-keepattributes SourceFile,LineNumberTable  # for readable stack traces
-renamesourcefileattribute SourceFile  # for crash deobfuscation
```

The `SourceFile,LineNumberTable` + `renamesourcefileattribute` pair makes stack traces post-obfuscation deobfuscatable via `mapping.txt`.

## Common keep patterns

**Annotation-driven, narrow:**

```proguard
# Keep Moshi-annotated data classes — class itself can be obfuscated, fields can't
-keepclassmembers,allowobfuscation,allowshrinking class * {
    @com.squareup.moshi.Json *;
}

# Keep Retrofit interface method signatures
-keep interface com.kozinga.api.* {
    @retrofit2.http.* <methods>;
}
```

**Inheritance-driven:**

```proguard
# Keep custom Parcelables (Parcelable.Creator is reflected)
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# Keep custom View constructors (XML inflation needs the (Context, AttributeSet) constructor)
-keep class * extends android.view.View {
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
}
```

**Native bridge:**

```proguard
# Keep native method names (JNI requires unobfuscated names)
-keepclasseswithmembernames class * {
    native <methods>;
}
```

## `-dontwarn`

R8 sometimes warns about referenced-but-unresolved classes. Library `consumer-rules.pro` files often include `-dontwarn` for optional dependencies:

```proguard
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
```

These libraries (OkHttp ships them) might not be on the classpath, but their absence is fine. `-dontwarn` suppresses the noise.

**Use `-dontwarn` sparingly and specifically.** `-dontwarn **` masks real errors. Always target the specific package whose absence you've verified is safe.

## `-keepclasseswithmembers` vs `-keep`

Subtle distinction:

```proguard
# -keep: always keep this class regardless of usage
-keep class com.example.Foo { *; }

# -keepclasseswithmembers: keep the class IF it has the specified members
-keepclasseswithmembers class com.example.Foo {
    @com.example.Keep <methods>;
}
```

The second only keeps the class when there's an `@Keep`-annotated method. If `@Keep` is removed, R8 will shrink the class away (because the *condition* — having those members — no longer holds).

This is useful for "keep classes that have this annotation, but not all classes." Most reflection-using libraries' rules use this form.

## `-keep,allowobfuscation` and similar

Modifier flags on a `-keep` rule loosen what it prevents:

```proguard
# Keep the class (don't shrink it) but allow renaming:
-keep,allowobfuscation class com.example.Foo

# Keep the class (don't shrink it) but allow optimization:
-keep,allowoptimization class com.example.Foo

# Keep the class but allow both:
-keep,allowobfuscation,allowoptimization,allowshrinking class com.example.Foo
```

These let you opt back into specific R8 phases for matched classes. Use when the *only* reason you're keeping something is reflection-by-annotation-but-not-by-name. The `allowshrinking` modifier with `-keep` is uncommon but valid.

## Review heuristic

When you see a `-keep` rule, ask:

1. **Does anything actually reflect on this?** If not, delete.
2. **Does reflection need the class name to be stable?** If not, add `,allowobfuscation`.
3. **Does reflection need the class itself to exist when no other code references it?** If not, switch to `-keepclassmembers` or use the `,allowshrinking` modifier.
4. **Are all members reflected, or only annotated ones?** If only annotated, narrow with `@Annotation *` syntax.
5. **Is this rule covered by a library's `consumer-rules.pro`?** If yes, delete (duplicate).

Most app-level `-keep` rules can be narrowed by 50%+ via this checklist.

## `@Keep` annotation

AGP ships `androidx.annotation.Keep`. Annotating a class/method with `@Keep` is equivalent to:

```proguard
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
```

These rules are in `proguard-android-optimize.txt`, so `@Keep` works out of the box.

**Use `@Keep` for one-off cases** (a single class that reflection touches) rather than adding a `-keep` rule. Easier to audit at the call site.

## Common pitfalls

- **`-keep class com.kozinga.** { *; }`** — defeats shrinking for entire app code. Audit and narrow.
- **`-keepattributes *`** — keeps every attribute. Bloats APK. Specify what you need.
- **`-keep class * implements Serializable`** — copy-pasted from old ProGuard rules. Only needed if you're actually doing `ObjectInputStream`-style serialization, which most modern apps aren't.
- **Forgetting `,allowobfuscation`** on rules where the class is reflected by annotation but not by name — leaves names un-shortened unnecessarily.
- **Adding library rules to app-level `proguard-rules.pro`** when the library ships `consumer-rules.pro` — duplication, drift. Trust the library's rules.
- **`-keepnames` when `-keep` is meant** — preserves the name but lets R8 remove the class. The class is gone at runtime; reflection still fails with `ClassNotFoundException`.
- **Wildcards used too aggressively** — `*` matches one package segment; `**` is recursive. Pick deliberately.
