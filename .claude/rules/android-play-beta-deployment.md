---
description: Patterns for shipping Android apps to Google Play beta tracks (internal / closed / open) — versionCode monotonicity, Play App Signing, AAB vs APK, service-account JSON for CI, ProGuard/R8 mapping upload, gotchas
globs: "**/{Fastfile,Appfile,build.gradle,build.gradle.kts,settings.gradle,settings.gradle.kts,gradle.properties,keystore.properties,proguard-rules.pro,*.yml,*.yaml}"
---

# Google Play Beta Deployment

Shipping an Android beta is mostly about *not* doing things that lock you out forever. The signing-key model has irreversible failure modes — lose the app signing key without Play App Signing enrolled, and your app is permanently un-updatable for existing users. The `versionCode` rules are similar — once Play has accepted a number, it's burned. These rules pin the conventions that keep teams out of unrecoverable states and document the canonical paths through the tooling.

## Versioning Discipline

Two numbers, both in `build.gradle.kts`'s `defaultConfig {}`:

- **`versionCode`** — integer, must monotonically increment with every upload to Play. **Reuse is rejected** — Play silently ignores any upload with a `versionCode` ≤ the one already in the same track. Use a monotonic source (commit count, build number, or a date-derived integer).
- **`versionName`** — string, user-visible. Semver-ish (`1.2.3`) is the convention but Play doesn't enforce it.

```kotlin
android {
    defaultConfig {
        // Don't hardcode these — compute in CI. See "Versioning Automation" below.
        versionCode = 142     // monotonic; never reused
        versionName = "1.4.2" // user-visible; reuse is fine
    }
}
```

**Versioning Automation:**

```kotlin
// In build.gradle.kts — compute versionCode from a CI-provided env var,
// falling back to a local-dev sentinel.
val buildNumber: Int = (System.getenv("BUILD_NUMBER") ?: "1").toInt()
android {
    defaultConfig {
        versionCode = buildNumber
        versionName = providers.gradleProperty("appVersionName").orNull ?: "0.0.0-dev"
    }
}
```

Then in CI:

```bash
# GitHub Actions: monotonic from run number, namespaced by repo
export BUILD_NUMBER="${GITHUB_RUN_NUMBER}"
./gradlew bundleRelease
```

**Never hardcode** `versionCode` in source control and bump it in PR commits — the merge order on `main` becomes load-bearing, and parallel branches can re-collide.

## Play App Signing — Use It

Play App Signing (introduced 2017, mandatory for new apps since August 2021) splits signing into two keys:

- **App signing key** — held by Google. Used to sign the artifact actually delivered to user devices. **You never see this key.**
- **Upload key** — held by you. Used to sign uploads to Play Console. Google verifies the upload key, then strips your signature and re-signs with the app signing key.

**Why this matters:** if you lose the upload key, you can reset it via Play Console (Google has the app signing key — your app keeps working). If you signed without Play App Signing and lose the app signing key, you cannot publish updates to existing users — they'd have to uninstall and reinstall a new app at a new package name.

**Concrete guidance:**
- **Enroll in Play App Signing for every new app.** It's the default in Play Console now; opt-out is hidden. Don't.
- **Generate a fresh upload key** (`.jks`) for each app, not a shared "all our apps" key.
- **Back up the upload key** out of band (1Password / a sealed envelope / your team's secrets manager). If you also lose the upload key without Play access, recovery requires a Play Console support ticket.

Keystore creation (one-time):

```bash
keytool -genkeypair -v \
  -keystore upload.keystore \
  -alias upload \
  -keyalg RSA -keysize 2048 -validity 25000 \
  -storepass "$KEYSTORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "CN=My App, O=My Team, C=US"
```

Gradle release-signing config:

```kotlin
android {
    signingConfigs {
        create("release") {
            // Read from gradle.properties OR env, never hardcode.
            // gradle.properties itself goes in .gitignore — see android-gradle-conventions.md
            storeFile = file(providers.gradleProperty("ANDROID_UPLOAD_KEYSTORE_PATH").get())
            storePassword = providers.gradleProperty("ANDROID_UPLOAD_KEYSTORE_PASSWORD").get()
            keyAlias = providers.gradleProperty("ANDROID_UPLOAD_KEY_ALIAS").get()
            keyPassword = providers.gradleProperty("ANDROID_UPLOAD_KEY_PASSWORD").get()
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}
```

In CI, decode the keystore from a secret to disk before the gradle build:

```yaml
- name: Decode keystore
  env:
    KEYSTORE_BASE64: ${{ secrets.UPLOAD_KEYSTORE_BASE64 }}
  run: |
    echo "$KEYSTORE_BASE64" | base64 --decode > $RUNNER_TEMP/upload.keystore
    echo "ANDROID_UPLOAD_KEYSTORE_PATH=$RUNNER_TEMP/upload.keystore" >> "$GITHUB_ENV"
```

## AAB vs APK — Use AAB

For apps published to Play **after August 2021**, Play requires Android App Bundles (`.aab`). APK uploads are accepted only for apps published before that cutoff (legacy).

- **`./gradlew bundleRelease`** → produces a `.aab` in `app/build/outputs/bundle/release/`. This is the artifact you upload.
- **`./gradlew assembleRelease`** → produces a `.apk`. Use only for sideloading, internal direct-install testing (Firebase App Distribution accepts both), or non-Play distribution channels.
- **`bundletool`** can convert a `.aab` into device-specific APKs locally for testing — useful when you need to install on a physical device exactly what Play would install for that device profile.

```bash
# Generate device-specific APKs from a .aab for local testing
bundletool build-apks \
  --bundle=app/build/outputs/bundle/release/app-release.aab \
  --output=app/build/outputs/apks/app.apks \
  --ks=upload.keystore \
  --ks-pass=pass:"$KEYSTORE_PASSWORD" \
  --ks-key-alias=upload

# Install on connected device — bundletool picks the right APK split
bundletool install-apks --apks=app/build/outputs/apks/app.apks
```

## Play Console Testing Tracks

Three pre-release tracks. Pick the right one for the audience:

- **Internal testing** — up to 100 testers (Google account emails), instant publish (no review), good for the team itself. Promoting from internal to closed/open is one click; deployments are fast.
- **Closed testing** — testers added by email list or Google Group, larger groups OK. The **first** new track requires a one-time review (~few hours to ~1 day). Subsequent updates within the same track go live without re-review.
- **Open testing** — public listing on Play Store with an "early access" affordance; users opt in via a public URL. Same review pattern as closed.

**Practical implications:**
- For tight iteration loops, use **internal testing**. No review delay.
- For wider feedback before public launch, **closed** > **open** — fewer support-ticket-from-strangers surprises.
- **All three tracks are version-locked** — a newer build in a "higher" track (production > open > closed > internal) blocks older builds in lower tracks. Plan your version sequence accordingly.

## Service Account JSON for CI

For automated uploads (`./gradlew publishReleaseBundle` via Triple-T, `fastlane supply`, or direct Play Developer API calls), you need a service account with Play Console access:

1. **Google Cloud Console** → IAM & Admin → Service Accounts → Create. Generate a JSON key.
2. **Play Console** → Settings → Developer account → API access → link the service account to a Play project, grant the role: minimum "Release manager" (can upload + manage tracks; can't change account settings).
3. **Store the JSON** as a single CI secret. Decode at use time:

```yaml
- name: Decode Play service account
  env:
    PLAY_SA_JSON: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
  run: |
    echo "$PLAY_SA_JSON" > $RUNNER_TEMP/play-sa.json
    echo "PLAY_SERVICE_ACCOUNT_JSON=$RUNNER_TEMP/play-sa.json" >> "$GITHUB_ENV"
```

**Permissions discipline:** grant the service account *only* the apps it needs to publish, and *only* the role it needs ("Release manager," not "Admin"). One compromised service account JSON should not give attackers control of every app on your developer account.

## Upload Tools — Tool-Agnostic Patterns

Three canonical paths, all production-grade:

- **[Triple-T `gradle-play-publisher`](https://github.com/Triple-T/gradle-play-publisher)** — Kotlin DSL gradle plugin. Apply once, configure once, then `./gradlew publishReleaseBundle` uploads. Lowest friction for Gradle-based projects.
- **[`fastlane supply`](https://docs.fastlane.tools/actions/supply/)** — Ruby-based; consistent CLI with the iOS side if you already use fastlane for both platforms.
- **Play Developer API directly** — `curl` calls or a small script. Maximum control, most code; consider only when the above don't fit a niche need.

Triple-T setup (recommended for new Android-only projects):

```kotlin
// app/build.gradle.kts
plugins {
    id("com.github.triplet.play") version "3.10.1"
}

play {
    serviceAccountCredentials.set(file(providers.gradleProperty("playServiceAccountPath").get()))
    track.set("internal")                     // internal | alpha (closed) | beta (open) | production
    releaseStatus.set(com.github.triplet.gradle.androidpublisher.ReleaseStatus.DRAFT)  // or COMPLETED
    defaultToAppBundles.set(true)             // upload .aab by default
}
```

Then in CI:

```yaml
- name: Publish to Play internal track
  env:
    PLAY_SA_PATH: ${{ env.PLAY_SERVICE_ACCOUNT_JSON }}
  run: ./gradlew publishReleaseBundle -PplayServiceAccountPath="$PLAY_SA_PATH"
```

## ProGuard / R8 — Mapping File Upload

Release builds with `isMinifyEnabled = true` produce a `mapping.txt` (obfuscation map) in `app/build/outputs/mapping/release/`. Without it, crash stacks from testers show as garbage like `a.a.b()`.

**Where the mapping goes:**

- **Play Console**: auto-uploaded as part of the AAB. Crash reports in Play Console are automatically deobfuscated.
- **Firebase Crashlytics**: the Firebase Gradle plugin (`firebase-crashlytics-gradle`) auto-uploads `mapping.txt` on Release builds when `firebaseCrashlytics { mappingFileUploadEnabled = true }` is set.
- **Sentry**: the Sentry Gradle plugin handles upload. Configure with the auth token; it runs as part of the release build task.

Verify mapping is being uploaded after every release. Forgetting this turns every tester crash report into a guessing game.

```kotlin
// build.gradle.kts (app)
android {
    buildTypes {
        release {
            firebaseCrashlytics {
                mappingFileUploadEnabled = true  // explicit; default behavior changes across plugin versions
            }
        }
    }
}
```

See the bundle's `r8-shrink-pro` skill for in-depth ProGuard rule review.

## Build Reproducibility

For Play beta builds you'll have to debug later:

- **Lock dependency versions** via the Gradle version catalog (`gradle/libs.versions.toml` — see `android-gradle-conventions.md`).
- **Commit `gradle/wrapper/`** — pins the Gradle version used for the build.
- **Pin Android Gradle Plugin** in the catalog.
- **Pin Java toolchain** — `kotlin { jvmToolchain(17) }` in app/build.gradle.kts; the toolchain auto-downloads.
- **Stamp the commit SHA** into the AAB via a `BuildConfig` field:

```kotlin
android {
    defaultConfig {
        buildConfigField("String", "GIT_COMMIT", "\"${System.getenv("GITHUB_SHA") ?: "local"}\"")
    }
}
```

## CI Patterns — Tool-Agnostic

The deploy-to-Play CI workflow has the same shape across tools:

1. **Checkout** at a known tag/commit.
2. **Set up the JDK and Android SDK.**
3. **Install secrets** — upload keystore (`.jks`), service account JSON.
4. **Compute monotonic `versionCode`** from a CI-derived source (run number, commit count).
5. **Build the release bundle**: `./gradlew bundleRelease`.
6. **Mapping upload** happens during the build itself (Firebase/Sentry plugins).
7. **Publish** to Play internal track via Triple-T or fastlane.
8. **Clean up secrets** — delete the keystore + JSON from the runner.

Tool-specific shapes:

- **fastlane**: `Fastfile` with `supply` action. Same `Fastfile` can ship to TestFlight (iOS) and Play (Android) — common when shipping a cross-platform app.
- **GitHub Actions** (raw Gradle): no Ruby; you write the steps. Best for Android-only teams that don't already have fastlane.
- **Bitrise / CircleCI / GitLab CI**: same shape; tool name changes.

## Common Gotchas (Ranked by Frequency)

1. **Reusing a `versionCode`** — Play silently rejects with "Version code N has already been used." Compute the version code from a monotonic CI source; never hardcode-and-commit.
2. **Uploading an APK instead of an AAB** — Play returns "This app must be published using an Android App Bundle." Always `./gradlew bundleRelease`, never `assembleRelease` for Play uploads.
3. **Wrong signing config** — Play returns "The Android App Bundle was not signed." Verify `signingConfig = signingConfigs.getByName("release")` is set on the `release` build type AND that the keystore env vars are present in CI.
4. **Wrong keystore for upload** — Play returns "Your APK or Android App Bundle was signed using a key that is being held by Google Play." Don't use the app signing key (you don't have it); use the upload key.
5. **Missing service account permission** — Play returns "Insufficient permissions." Service account needs at least "Release manager" on the specific Play app.
6. **`targetSdk` too low** — Play returns warnings and may block uploads to production. Bump `targetSdk` on the yearly schedule Google publishes.
7. **`mapping.txt` not uploaded to Crashlytics/Sentry** — crashes show as obfuscated stacks. Verify the auto-upload Gradle plugin is actually running by checking the build log for "Uploading mapping file."
8. **Beta tester didn't get the email invite** — most common: the invite expired (24h for closed track invites in some configurations) or went to spam. Provide the opt-in URL directly: `https://play.google.com/apps/internaltest?id=com.example.MyApp`.
9. **AAB rejected for permissions / declared features** — `<uses-permission>` declared but not actually used can trigger Play's automated review. Audit `AndroidManifest.xml` for stale entries.
10. **First closed-track upload sits in review for hours** — that's normal. Subsequent uploads to an already-reviewed track go live in minutes.

## Patterns to Follow

```yaml
# .github/workflows/play-internal.yml — minimum-viable canonical shape
name: Play Internal

on:
  workflow_dispatch:
  push:
    branches: [main]
    paths: ['android/**']

jobs:
  play-internal:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Set up Android SDK
        uses: android-actions/setup-android@v3

      - name: Decode upload keystore
        env:
          KEYSTORE_BASE64: ${{ secrets.UPLOAD_KEYSTORE_BASE64 }}
        run: |
          echo "$KEYSTORE_BASE64" | base64 --decode > "$RUNNER_TEMP/upload.keystore"
          echo "ANDROID_UPLOAD_KEYSTORE_PATH=$RUNNER_TEMP/upload.keystore" >> "$GITHUB_ENV"

      - name: Decode Play service account
        env:
          PLAY_SA_JSON: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
        run: |
          echo "$PLAY_SA_JSON" > "$RUNNER_TEMP/play-sa.json"
          echo "PLAY_SERVICE_ACCOUNT_PATH=$RUNNER_TEMP/play-sa.json" >> "$GITHUB_ENV"

      - name: Build and publish
        env:
          BUILD_NUMBER: ${{ github.run_number }}
          ANDROID_UPLOAD_KEYSTORE_PASSWORD: ${{ secrets.UPLOAD_KEYSTORE_PASSWORD }}
          ANDROID_UPLOAD_KEY_ALIAS:         ${{ secrets.UPLOAD_KEY_ALIAS }}
          ANDROID_UPLOAD_KEY_PASSWORD:      ${{ secrets.UPLOAD_KEY_PASSWORD }}
        working-directory: android
        run: |
          ./gradlew publishReleaseBundle \
            -PplayServiceAccountPath="$PLAY_SERVICE_ACCOUNT_PATH" \
            --no-daemon

      - name: Clean up secrets
        if: always()
        run: |
          rm -f "$RUNNER_TEMP/upload.keystore" "$RUNNER_TEMP/play-sa.json"
```

For fastlane equivalent, `Fastfile`:

```ruby
default_platform(:android)
platform :android do
  lane :beta do
    # Triple-T or supply — both work. supply uses the Play Developer API directly.
    gradle(task: 'clean bundleRelease')
    upload_to_play_store(
      track: 'internal',
      aab: 'app/build/outputs/bundle/release/app-release.aab',
      json_key: ENV['PLAY_SERVICE_ACCOUNT_PATH'],
      release_status: 'draft'    # require manual promotion to rollout
    )
  end
end
```
