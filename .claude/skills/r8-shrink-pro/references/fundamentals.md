# R8 Fundamentals

R8 is the default code shrinker, optimizer, and obfuscator for Android, introduced in AGP 3.4 and now standard in AGP 8.x. It replaced legacy ProGuard while remaining rule-compatible — your `proguard-rules.pro` files work unchanged.

## What R8 does

R8 has four phases:

1. **Shrinking** — removes unused classes, methods, and fields. Determines "used" by tracing from entry points (Application class, Activities, registered services) plus anything matched by `-keep` rules.
2. **Optimizing** — inlines methods, removes dead branches, merges classes, replaces unused parameters. Substantially reduces method count and improves runtime performance.
3. **Obfuscating** — renames classes, methods, fields to short names (`a`, `b`, `c`). Makes reverse-engineering harder; also reduces APK size.
4. **Repackaging** — flattens packages so everything ends up in the same short-named package. Further reduces APK size.

All four are controlled by the same rules. `-keep` opts out of all of them for matched classes.

## How to enable

In `build.gradle.kts`:

```kotlin
android {
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true   // also strip unused resources
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // Debug builds typically don't minify — too slow for iterative dev.
            // Set this true periodically to catch missing keep rules early.
            isMinifyEnabled = false
        }
    }
}
```

- **`isMinifyEnabled = true`** turns R8 on.
- **`isShrinkResources = true`** removes unused resources (`drawable-*`, `string-*`, etc.). Requires `isMinifyEnabled = true`.
- **`proguard-android-optimize.txt`** is AGP's bundled rules — covers Android framework classes, common annotations, JNI hooks. Always include.
- **`proguard-rules.pro`** is your app's rules.

## ProGuard vs R8

| Concern | ProGuard (legacy) | R8 (current) |
|---------|-------------------|--------------|
| Speed | Slow | Faster (~30%) |
| Optimization | Decent | Better (inlining is more aggressive) |
| Rule syntax | Original | Same — backwards compatible |
| Bundled with AGP | No (third-party) | Yes |
| Kotlin metadata handling | Manual | Automatic |
| `-keepkotlinmetadata` | Required | Default in full mode |

**There's no reason to use legacy ProGuard with modern AGP.** R8 is strictly better.

## Full mode vs compatibility mode

Set in `gradle.properties`:

```properties
android.enableR8.fullMode=true
```

- **Full mode (recommended for new apps)** — R8 is more aggressive about optimization. Some old ProGuard rules become unnecessary.
- **Compatibility mode (default in older AGP versions)** — exact ProGuard parity. Use for apps with extensive legacy `-keep` rules that haven't been audited for R8 full-mode compatibility.

Full mode in AGP 8.x:
- Removes parameter names not used by reflection.
- More aggressive inlining.
- Doesn't apply `-keep` to Kotlin reflection metadata by default — annotated classes still work, but unannotated reflection on member names might need extra rules.

**If migrating from compat → full**, build a release variant and test thoroughly first. Some library rules assume compat-mode behavior.

## What R8 won't touch

Some classes are entry points R8 considers "kept" without any explicit rule:

- **Application subclass** — referenced by AndroidManifest's `android:name`.
- **Activity / Service / BroadcastReceiver / ContentProvider subclasses** registered in the manifest.
- **Classes named in `<intent-filter>`**.
- **Classes used by `XmlInflater`** (Views referenced in XML).
- **Classes referenced by native code via JNI** — *if* you've kept their methods with `@Keep` or appropriate rules (see `library-keep-rules.md`).

Everything else is fair game for shrinking.

## `isShrinkResources` and resource keep rules

`isShrinkResources = true` removes unused drawable / string / dimen / layout resources. Most "unused" detection works via the same call graph R8 builds for code. Some patterns need explicit hints:

- **Resources referenced via `getResources().getIdentifier(...)`** (lookup by name string) — R8 can't trace these. Use a `res/raw/keep.xml` to declare them:

  ```xml
  <?xml version="1.0" encoding="utf-8"?>
  <resources xmlns:tools="http://schemas.android.com/tools"
      tools:keep="@drawable/dynamic_*,@string/error_*"
      tools:discard="@drawable/old_*" />
  ```

- **Resources only referenced from native code** — same `tools:keep` mechanism.

## How to read R8's output

Add to `proguard-rules.pro` to get reports:

```proguard
-printusage build/outputs/mapping/release/usage.txt
-printseeds build/outputs/mapping/release/seeds.txt
-printmapping build/outputs/mapping/release/mapping.txt
-printconfiguration build/outputs/mapping/release/configuration.txt
```

After a release build:
- **`usage.txt`** — classes/members R8 *removed*. Useful for shrinking sanity checks.
- **`seeds.txt`** — classes/members R8 *kept* due to your rules. Useful for "wait, why is this kept?" investigations.
- **`mapping.txt`** — obfuscation map (original → renamed). Critical for deobfuscating crash reports.
- **`configuration.txt`** — the final, merged set of rules R8 used (your rules + library `consumer-rules.pro` + AGP defaults).

## Build-time vs runtime crashes

R8 failures take two forms:

- **Build-time:** missing rules can cause R8 to fail with a "missing class" error during the build. Easy to spot — the build fails.
- **Runtime:** missing rules cause classes/methods to be stripped that runtime reflection needs. **Build passes, app crashes in release with `ClassNotFoundException` / `NoSuchMethodException`.** Much harder to spot until you test the release build.

**Always test minified release builds.** A common workflow: enable `isMinifyEnabled = true` on a `staging` build variant that mirrors release, and run UI tests against it. Catches reflection issues before production.

## Common pitfalls

- **`isMinifyEnabled = true` in release but `false` in debug** — you only discover missing rules when you build for release, often the day before a launch. Periodically enable for debug builds too.
- **`isShrinkResources = true` without `isMinifyEnabled = true`** — won't work; resource shrinking depends on code shrinking. AGP will warn.
- **Adding `-dontoptimize` to suppress an R8 issue** — defeats the optimization step. Better to find the right keep rule than disable optimization.
- **Adding `-dontobfuscate`** — same problem. Stack traces from production become readable but APK is larger and reverse-engineering trivial. Use a `mapping.txt` deobfuscation workflow instead.
- **Bundled `proguard-android-optimize.txt` mistakenly excluded** — getDefaultProguardFile gives the right one. Don't replace it with a hand-rolled minimal set.
- **Different rules in debug vs release** — release-only rules mean release-only behavior. Hard to debug. Keep rule sets identical; vary only `isMinifyEnabled`.

## When you don't need R8

- **Library modules** — don't enable `isMinifyEnabled` for library modules; consumers handle their own minification. Libraries ship `consumer-rules.pro` to tell consumers what to keep.
- **Test variants** — test code rarely benefits from minification and the symbol mangling breaks reflection-using test libraries.
- **Debug variants** — slows the build for negligible runtime gain during development.

The standard pattern: `isMinifyEnabled = true` on **release** only; everything else is `false`.
