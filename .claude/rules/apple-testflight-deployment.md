---
description: Patterns for shipping iOS / macOS / tvOS / watchOS / visionOS apps to TestFlight — versioning, App Store Connect API auth, archive + export, code signing, tester groups, beta review, dSYM upload, CI integration
globs: "**/{Fastfile,Appfile,Matchfile,Deliverfile,Snapfile,Scanfile,Gymfile,exportOptions.plist,ExportOptions.plist},.github/workflows/*.{yml,yaml},.gitlab-ci.yml,bitrise.yml,.circleci/config.yml"
paths:
  - "**/{Fastfile,Appfile,Matchfile,Deliverfile,Snapfile,Scanfile,Gymfile,exportOptions.plist,ExportOptions.plist}"
  - ".github/workflows/*.{yml,yaml}"
  - ".gitlab-ci.yml"
  - "bitrise.yml"
  - ".circleci/config.yml"
must:
  - "`CFBundleVersion` always increases and comes from CI; never hardcode or reuse it."
  - "Authenticate with an App Store Connect API key (.p8) stored as a CI secret, not an app-specific password."
  - "Use manual signing in CI and never commit `.p12` certificates or profiles."
  - "Export with `method: app-store-connect` and upload dSYMs to your crash reporter."
---

# Apple TestFlight Deployment

The must-follow rules for shipping builds to TestFlight. The commands, `ExportOptions.plist` fields, signing setups, privacy-manifest and age-assurance detail, Xcode 27 toolchain notes, gotchas, and a sample workflow are in [`beta-deployment-pro/references/testflight.md`](../skills/beta-deployment-pro/references/testflight.md); read the matching section only when a line below isn't enough. Set up or review a pipeline with `beta-deployment-pro`.

## Versioning

- **`CFBundleVersion` increases on every upload and comes from CI** (run number or commit count). Never hardcode or reuse it.
- `CFBundleShortVersionString` is the user-visible version. Bumping it triggers a new external beta review, so don't bump it mid-cycle.

## Auth and signing

- **App Store Connect API key** (issuer ID, key ID, `.p8`) stored as CI secrets. Not an Apple ID with an app-specific password.
- **Manual signing in CI** with fastlane `match` or a base64 keychain import. Never commit `.p12` certificates, profiles, or the `.p8`, and delete them from the runner afterwards.

## Archive, export, upload

- Archive the Release configuration, export with **`method: app-store-connect`** and `signingStyle: manual`, upload with `altool` or the ASC API.
- **Upload dSYMs** from the `.xcarchive` to your crash reporter, and set `uploadSymbols: true`.
- Make sure entitlements exist for every capability (push, IAP, App Groups, iCloud).

## Submission gates

- **`PrivacyInfo.xcprivacy`** declares every required-reason API, collected data type, and tracking domain, and third-party SDKs ship their own manifests. Review Xcode's privacy report each release; a cloud AI call is data collection.
- **Age assurance**: answer the social-media capability question, gate social features with `DeclaredAgeRange`, and keep the age-rating questionnaire and privacy documentation current.

## Reproducibility and CI

- Commit `Package.resolved` (or `Podfile.lock`), **pin the Xcode version** on a pinned Apple-silicon runner, and pin fastlane through `Gemfile.lock`. Stamp the commit SHA into the build.
- **Xcode 27** needs Apple silicon and macOS Tahoe 26.4+, drops `x86_64` at deployment target 27, and rejects `-ld_classic`. Treat an SDK bump as a UI change, since iOS 27 SDK apps are resizable by default.
- Internal testers get builds without review; the first build of each version for external testers goes through beta review.
