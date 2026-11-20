---
name: swift-library-pro
description: Ships and maintains Swift packages and Apple frameworks that other apps depend on — public API and source/binary compatibility review, SemVer and automated breaking-change checks (diagnose-api-breaking-changes), deprecation, library evolution and module stability, XCFrameworks and binary targets with signatures and privacy manifests, multi-platform CI, DocC and Swift Package Index, and the release process. Use when building a library rather than an app, before tagging a release, when deciding whether a change is breaking, or when distributing a binary SDK.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
---

Keep a Swift library safe to depend on: consumers upgrade without surprise, binaries load in their apps, and every release says honestly what changed. This is the deep companion to the always-on `apple-library-authoring.md` rule. `swift-package-pro` reviews the manifest and module layout; `swift-docc-pro` reviews doc comments; this skill owns compatibility, distribution, and release. Report only genuine problems.

Pick the mode from the request:

- **Review a change**: classify every public-API difference as additive, source-breaking, or binary-breaking (`references/api-stability.md`), then name the required version bump.
- **Prepare a release**: run the release checklist in `references/ci-and-release.md` and draft the CHANGELOG entry.
- **Ship a binary**: build, sign, and package an XCFramework and its `.binaryTarget` (`references/binary-distribution.md`).
- **Set up**: a new library repo. Produce the CI workflow, `.spi.yml`, CHANGELOG, and breaking-change gate.

Load only the reference you need:

- `references/api-stability.md` — public surface design, `package` access, what breaks source vs binary compatibility, enums that must grow, protocols, isolation and `Sendable` as API, `@_spi`, deprecation lifecycle, `diagnose-api-breaking-changes`, and the API Design Guidelines.
- `references/binary-distribution.md` — when to ship a binary, library evolution and module stability, `@frozen` / `@inlinable` / `@usableFromInline`, building an XCFramework, dSYMs, signing, privacy manifests for SDKs, `.binaryTarget` and checksums, mixed Objective-C frameworks, and gotchas.
- `references/ci-and-release.md` — the platform matrix (`swift test`, `xcodebuild` per platform, Linux, oldest and newest Xcode), API-break gate, docs build, Swift Package Index `.spi.yml`, package traits for optional dependencies, versioning and tags, the release checklist, and a GitHub Actions workflow.

## Review Checklist

1. **Surface**: nothing is `public` that a consumer doesn't call; cross-module helpers are `package`; no public globals or retroactive conformances.
2. **Compatibility**: every change since the last tag classified; the version bump matches the worst one; `diagnose-api-breaking-changes` runs in CI.
3. **Deprecation**: removals were deprecated with `renamed:` / `message:` for at least one MINOR release first.
4. **Concurrency as API**: public types declare `Sendable` and isolation deliberately; no change tightens either within a major version.
5. **Platforms**: every platform in `platforms:` builds in CI; minimum OS unchanged unless MAJOR.
6. **Binary** (if shipped): library evolution on, all slices present, signed, privacy manifest inside, checksum matches, no module/type name clash.
7. **Docs**: every public symbol documented, DocC builds without warnings, README sample compiles.
8. **Release**: tag `X.Y.Z`, CHANGELOG entry, `Package.resolved` not committed.

## Output Format

Organize findings by file. For each issue give the file and lines, the rule broken, the consumer impact (who breaks and how), and a before/after fix. For a change review, end with a table of public-API differences and the required SemVer bump. Finish with a prioritized summary.

## Companion skills

- [`Swift-API-Design-Guidelines-Agent-Skill`](https://github.com/Erikote04/Swift-API-Design-Guidelines-Agent-Skill) by Erik Sebastián de Erice Jerez (MIT) reviews naming, argument labels, and clarity at the point of use against Apple's API Design Guidelines. Install it alongside this bundle for naming reviews; this skill doesn't repeat them.
