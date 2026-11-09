---
name: beta-deployment-pro
description: Sets up and reviews beta release pipelines for TestFlight and Google Play testing tracks — CI-derived build numbers, App Store Connect API keys and Play service accounts, code signing and Play App Signing, archive/export/upload and AAB builds, dSYM and mapping.txt upload, privacy manifests, age assurance, Data safety, reproducible CI, and upload error triage. Use when creating a release workflow, an upload is rejected, or before the first external beta.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
---

Make beta releases repeatable: every build has a unique number from CI, secrets never touch the repo, crashes come back symbolicated, and the store's submission gates pass on the first try. This is the deep companion to the always-on `apple-testflight-deployment.md` and `android-play-beta-deployment.md` rules. Report only genuine problems.

Pick the mode from the request:

- **Set up**: no pipeline yet. Build the workflow from the sample in the platform's reference and list the secrets to create.
- **Fix an upload**: a build was rejected or never appeared. Match the error against the platform's ranked gotchas first.
- **Review**: audit an existing pipeline against the checklist below.

Load only the reference for the platform in scope:

- `references/testflight.md` — versioning, App Store Connect API keys, archive, export, and upload commands, `ExportOptions.plist`, signing approaches, tester groups, dSYMs, privacy manifests, age assurance, reproducibility and Xcode 27 toolchain notes, CI tools, ranked gotchas, and a GitHub Actions workflow.
- `references/play-beta.md` — `versionCode` from CI, Play App Signing and keystore handling, AAB versus APK, testing tracks, service-account setup, upload tools, `mapping.txt` upload, Data safety, reproducibility, CI tools, ranked gotchas, and a GitHub Actions workflow.

## Review Checklist

1. **Build numbers** come from CI and always increase; nothing hardcoded in the project or committed.
2. **Credentials**: API key or service account in CI secrets with the least role; no `.p8`, `.p12`, profile, keystore, or JSON key in the repo; secrets removed from the runner after use.
3. **Signing**: manual signing in CI for Apple; Play App Signing with a per-app upload key for Android.
4. **Artifacts**: `method: app-store-connect` export, or an AAB from `bundleRelease`.
5. **Symbols**: dSYMs or `mapping.txt` reach the crash reporter and the store.
6. **Submission gates**: privacy manifest and age-assurance answers (Apple), Data safety form and `targetSdk` (Android) are current.
7. **Reproducibility**: pinned Xcode or JDK/AGP, lockfiles committed, commit SHA stamped into the build.

## Output Format

Group findings by severity: **blocking** (committed secrets, reused or hardcoded build numbers, wrong export method or artifact type, failing submission gates), **degraded** (symbols not uploaded, unpinned toolchains, over-privileged credentials), **polish** (SHA stamping, tester-group setup). Give each as file:line, what goes wrong at upload or in the field, and the fix. End with the count per severity and the first three fixes.
