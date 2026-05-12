# `mapping.txt`: Deobfuscation Workflow

Every minified release build produces a `mapping.txt` file that records the obfuscation map (original → renamed). **Lose `mapping.txt` for a release, and crash reports from that release become unreadable.** This is the single most important operational concern around R8.

## Where mapping.txt lives

After a release build:

```
app/build/outputs/mapping/release/
├── mapping.txt                # the obfuscation map
├── seeds.txt                  # what got kept (if -printseeds enabled)
├── usage.txt                  # what got removed (if -printusage enabled)
├── configuration.txt          # final merged rules (if -printconfiguration enabled)
└── missing_rules.txt          # missing keep rules R8 detected (if any)
```

The mapping file is named with the build variant + flavor — `mapping/release/mapping.txt`, `mapping/freeRelease/mapping.txt`, etc.

## What's in mapping.txt

Plain text. Format:

```
com.kozinga.feature.home.HomeViewModel -> a.b.c.a:
    androidx.lifecycle.MutableLiveData state -> a
    void refresh() -> a
    void onItemClick(com.kozinga.models.Item) -> a
```

- Class name `com.kozinga.feature.home.HomeViewModel` was renamed to `a.b.c.a`.
- Field `state` was renamed to `a`.
- Methods `refresh()` and `onItemClick(...)` were both renamed to `a` (allowed because overload signature differs).

## Retention strategy

**Always preserve mapping.txt for every release.** Three common approaches:

### 1. Crashlytics auto-upload (most common)

Firebase Crashlytics uploads `mapping.txt` automatically with each release. Add the Crashlytics Gradle plugin:

```toml
# libs.versions.toml
[plugins]
gms-google-services = { id = "com.google.gms.google-services", version = "4.4.2" }
firebase-crashlytics = { id = "com.google.firebase.crashlytics", version = "3.0.2" }
```

```kotlin
// app/build.gradle.kts
plugins {
    alias(libs.plugins.gms.google.services)
    alias(libs.plugins.firebase.crashlytics)
}

android {
    buildTypes {
        release {
            isMinifyEnabled = true
            firebaseCrashlytics {
                mappingFileUploadEnabled = true
            }
        }
    }
}
```

Crashes reported to Crashlytics are auto-deobfuscated.

### 2. Play Console upload

Google Play accepts `mapping.txt` for app bundle uploads. Either:

- **AAB-bundled (modern):** Android Studio's "Generate Signed App Bundle" bundles `mapping.txt` automatically.
- **Manual:** Play Console → App bundle explorer → Re-tracing → upload mapping file.

Stack traces reported through Play Console's Vitals → ANRs and crashes are auto-deobfuscated.

### 3. Git / artifact-store retention

For self-hosted crash reporting (Sentry, Bugsnag, custom), upload `mapping.txt` to your crash-reporter's symbolication service per release. Plus, commit it to a versioned artifact store or release-tag git LFS for archival.

**Don't commit mapping.txt to your main source repo** — it's a build output (regenerated on every release) and adds noise.

## Manual deobfuscation: `retrace`

If you have an obfuscated stack trace and the matching `mapping.txt`, AGP ships a `retrace` command:

```bash
# Path to retrace varies by Android Studio install:
~/Android/Sdk/tools/proguard/bin/retrace.sh mapping.txt obfuscated_stack.txt

# Or via Java directly:
java -jar /path/to/retrace.jar mapping.txt obfuscated_stack.txt
```

Output: the original-class-name stack trace.

Modern Android Studio ships a UI for this: **Build → Analyze APK → Deobfuscate → upload mapping → paste stack trace.**

## Sample obfuscated crash + deobfuscation

**Obfuscated stack trace (from Play Console or Crashlytics in worst case):**

```
java.lang.NullPointerException
    at a.b.c.a.a(Unknown Source:42)
    at a.b.c.b.a(Unknown Source:17)
    at android.os.Handler.handleCallback(Handler.java:938)
```

**After retrace + mapping.txt:**

```
java.lang.NullPointerException
    at com.kozinga.feature.home.HomeViewModel.refresh(HomeViewModel.kt:42)
    at com.kozinga.feature.home.HomeScreen.LoadingButton$lambda$5(HomeScreen.kt:17)
    at android.os.Handler.handleCallback(Handler.java:938)
```

Now it's actionable.

## Source-file & line-number attributes

For line numbers to survive obfuscation, your `proguard-rules.pro` must include:

```proguard
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
```

These are in `proguard-android-optimize.txt` by default. If you've replaced that file with a hand-rolled set, you need to add these explicitly.

Without `SourceFile` + `LineNumberTable`, your obfuscated stack traces look like:

```
at a.b.c.a.a(Unknown Source)
```

— no line numbers, much harder to localize bugs.

## Missing rules report (R8 full mode)

R8 in full mode emits `missing_rules.txt` when there are classes it can't resolve:

```
app/build/outputs/mapping/release/missing_rules.txt
```

If this file exists and is non-empty, R8 is telling you "I might have stripped something I shouldn't." Read it before shipping.

Typical contents:

```
# Missing rules for class com.example.LegacyClass referenced from:
#   com.kozinga.feature.foo.FooViewModel
-dontwarn com.example.LegacyClass
```

R8 suggests `-dontwarn` rules; copy them into your `proguard-rules.pro` if the referenced class is genuinely optional.

## Verifying mapping.txt is bundled

```bash
# AAB:
unzip -l app-release.aab | grep mapping

# APK with Crashlytics:
unzip -p app-release.apk META-INF/MANIFEST.MF | grep mapping
```

Crashlytics-bundled mapping is uploaded out-of-band; APKs themselves shouldn't include `mapping.txt` (that defeats obfuscation).

## CI workflow

In your release CI workflow:

```yaml
- name: Build release bundle
  run: ./gradlew bundleRelease

- name: Upload mapping file to Crashlytics
  run: ./gradlew uploadCrashlyticsMappingFileRelease

- name: Archive mapping.txt as build artifact
  uses: actions/upload-artifact@v4
  with:
    name: mapping-${{ github.ref_name }}
    path: app/build/outputs/mapping/release/mapping.txt
    retention-days: 90
```

The third step is insurance — if Crashlytics retention is shorter than your debugging window, you'll still have it.

## Common pitfalls

- **Mapping.txt lost** because it wasn't archived. Months later, you can't read a production crash. Always archive.
- **Wrong mapping.txt for the version** — you uploaded version 1.5.0's mapping to debug a crash from 1.4.2. Match mapping to version.
- **`-renamesourcefileattribute SourceFile` missing** — line numbers preserved but source-file column reads `SourceFile` instead of the real `.kt` name. Less useful in stack traces. The rule is in `proguard-android-optimize.txt`; don't replace the default.
- **No `SourceFile,LineNumberTable` kept** — stack traces read `(Unknown Source)`. Always keep these attributes.
- **Crashlytics plugin in `build.gradle.kts` but `mappingFileUploadEnabled = false`** — plugin builds, mapping not uploaded. Verify after a release that Crashlytics's "deobfuscated" indicator shows for crashes.
- **Mapping committed to source repo** — diff noise, blob size grows. Use CI artifacts or Crashlytics upload instead.
- **`-dontobfuscate` to "fix" the mapping problem** — defeats obfuscation entirely. APK is larger, code is reverse-engineerable. Just preserve `mapping.txt` properly.
