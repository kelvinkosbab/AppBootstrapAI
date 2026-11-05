---
name: xcode-security-pro
description: Audits and hardens Xcode build security — security compiler warnings and static-analyzer checks, Enhanced Security (ENABLE_ENHANCED_SECURITY, pointer authentication, hardened-process entitlements, typed allocators, C++ standard library hardening, Memory Tagging, checked pointer arithmetic), a phased rollout, a decision record for disabled settings, and adopting -fbounds-safety in C code. Use when reviewing build settings or entitlements for security, enabling Enhanced Security, or making C / C++ / Objective-C code memory-safer.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "Apple documentation on Enhanced Security, pointer authentication, Memory Integrity Enforcement, and -fbounds-safety, the Clang static analyzer and SafeBuffers docs, and the security-settings and bounds-safety agent skills Apple ships with Xcode 27 (as published by Artem Novichkov in artemnovichkov/xcode-skills)"
---

Audit an Xcode project's security-related build settings and entitlements, and help adopt the memory-safety features Xcode offers. This is the deep-review companion to the `apple-build-security.md` rule.

> **Sources.** Grounded in Apple's documentation and in the "audit Xcode security settings" and "adopt C bounds safety" skills Apple bundles with Xcode 27, which [Artem Novichkov](https://github.com/artemnovichkov) extracted and published in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills). The guidance is rewritten and condensed for this bundle, not copied. Setting names change between Xcode releases: confirm each one with `xcodebuild -showBuildSettings` before recommending it.

Review process:

1. **Inventory.** Read the project's settings the way Xcode resolves them: `xcodebuild -showBuildSettings -project App.xcodeproj -target <T> -configuration Release` per target, plus `.xcconfig` files and the entitlements files. Record product type, languages (does the target compile any C, C++, or Objective-C?), deployment targets, and binary dependencies.
2. **Compiler warnings and analyzer checks** using `references/settings-reference.md`. Skip C-family warnings for a pure-Swift target and say so.
3. **Enhanced Security** using `references/enhanced-security.md`: whether it's enabled at project level, which entitlements are present, which product types qualify, and which binary dependencies block arm64e.
4. **Rollout and C bounds safety** using `references/rollout-and-bounds-safety.md`: propose the next phase, not everything at once, and for C code an `-fbounds-safety` plan file by file.
5. **Decision record.** Check for `docs/xcode-security-settings.md` (or the project's equivalent) listing every setting left off and why. Propose one if missing.

## Core Instructions

- **Recommend, then change with permission.** Build settings change binaries, entitlements change runtime behavior, and some features crash on violations by design. Show the diff and the expected effect; apply it only when asked.
- **Project level by default, target-level overrides only for a reason** (a binary dependency without an arm64e slice, a target type that doesn't support a feature). Every override goes in the decision record.
- **Respect explicit `NO`.** A setting turned off on purpose is a decision; ask for the reason and record it instead of flipping it.
- **Never weaken a setting to fix a build.** If enabling something breaks the build, the finding is the code or the dependency, not the setting.
- **Severity**: a security feature explicitly disabled without reason, or an analyzer check turned off > Enhanced Security not enabled on an eligible app > missing warnings > noisier optional checks.
- Cross-reference: Swift concurrency safety belongs to `swift-concurrency-pro`; Objective-C style to `apple-objc-best-practices.md`; release signing to `apple-testflight-deployment.md`.

## Output Format

Group findings by target, then by area (warnings, analyzer, Enhanced Security, entitlements, bounds safety). For each: the setting or entitlement, current value and where it's set, the recommended value, and what changes at build or run time. End with the proposed next phase and the decision-record entries to add.

Example finding:

### Target `Pantry` (application, Swift + C)

**`ENABLE_ENHANCED_SECURITY` is unset.** The app is eligible and has no arm64e-blocking dependencies. Set it to `YES` at project level; it turns on pointer authentication, C++ library hardening, security warnings, and typed allocators. Add `com.apple.security.hardened-process` = `true` and `com.apple.security.hardened-process.enhanced-security-version-string` = `"2"` to `Pantry.entitlements`.
