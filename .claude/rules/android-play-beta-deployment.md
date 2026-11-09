---
description: Patterns for shipping Android apps to Google Play beta tracks (internal / closed / open) — versionCode monotonicity, Play App Signing, AAB vs APK, service-account JSON for CI, ProGuard/R8 mapping upload, gotchas
globs: "**/{Fastfile,Appfile,build.gradle,build.gradle.kts,settings.gradle,settings.gradle.kts,gradle.properties,keystore.properties,proguard-rules.pro},.github/workflows/*.{yml,yaml},.gitlab-ci.yml,bitrise.yml,.circleci/config.yml"
paths:
  - "**/{Fastfile,Appfile,build.gradle,build.gradle.kts,settings.gradle,settings.gradle.kts,gradle.properties,keystore.properties,proguard-rules.pro}"
  - ".github/workflows/*.{yml,yaml}"
  - ".gitlab-ci.yml"
  - "bitrise.yml"
  - ".circleci/config.yml"
must:
  - "`versionCode` comes from CI and always increases; never reuse or hand-edit it."
  - "Use Play App Signing and upload an AAB (`bundleRelease`), not an APK."
  - "Never commit keystores or the service-account JSON; decode them from CI secrets."
  - "Enable R8 for release and make sure `mapping.txt` reaches Play and your crash reporter."
---

# Google Play Beta Deployment

The must-follow rules for shipping builds to Play testing tracks. Gradle signing and versioning code, track details, service-account setup, upload-tool options, gotchas, and a sample workflow are in [`beta-deployment-pro/references/play-beta.md`](../skills/beta-deployment-pro/references/play-beta.md); read the matching section only when a line below isn't enough. Set up or review a pipeline with `beta-deployment-pro`; R8 rules go to `r8-shrink-pro`.

## Versioning

- **`versionCode` increases on every upload and comes from CI** (run number or commit count). Never reuse, hand-edit, or commit it.
- `versionName` is the user-visible version. Tracks are version-locked: a higher `versionCode` in a higher track shadows lower tracks.

## Signing and artifacts

- **Enroll in Play App Signing.** Google holds the app signing key; you hold a per-app upload key, backed up outside CI.
- **Upload an AAB** from `./gradlew bundleRelease`. APKs only for sideloading or non-Play channels (`bundletool` for local device testing).
- **Never commit keystores, `keystore.properties`, or the service-account JSON.** Decode them from CI secrets, read signing values from the environment, and delete them from the runner afterwards.

## CI access and upload

- A dedicated service account with the **Release manager** role on the app only.
- Upload with Triple-T `gradle-play-publisher`, `fastlane supply`, or the Play Developer API, to the internal track first and promote from there.

## R8 and symbols

- **R8 on for release** (`isMinifyEnabled` and `isShrinkResources`), with `mapping.txt` uploaded to Play and to your crash reporter (Crashlytics or Sentry Gradle plugin). Check the build log that the upload ran.

## Data safety

- **Keep the Data safety form true.** Re-check it whenever a new SDK lands; analytics, ads, crash, and cloud AI SDKs all collect on your behalf. It's versioned with the listing, so put it in the release checklist.

## Reproducibility

- Pin versions in `gradle/libs.versions.toml` (including AGP), commit `gradle/wrapper/`, set `jvmToolchain`, and stamp the commit SHA into `BuildConfig`.
- Keep `targetSdk` on Google's yearly schedule and remove unused permissions before upload.
