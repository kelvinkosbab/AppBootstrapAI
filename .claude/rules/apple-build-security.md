---
description: Xcode build security — keep security warnings and analyzer checks on for C-family code, enable Enhanced Security at project level with the hardened-process entitlements, override pointer authentication only per target for an arm64e-less dependency, roll out memory-safety features in phases, and record every disabled setting
globs: "**/*.{xcconfig,entitlements,pbxproj}"
paths:
  - "**/*.{xcconfig,entitlements,pbxproj}"
must:
  - "Set ENABLE_ENHANCED_SECURITY = YES at project level with the hardened-process entitlements on eligible apps."
  - "Disable pointer authentication only on the target that links an arm64e-less binary, and record why."
  - "Never weaken a security setting to make a build pass; fix the code or the dependency."
  - "Record every security setting left off in docs/xcode-security-settings.md."
---

# Xcode Build Security

Xcode 27 ships compiler, analyzer, and runtime protections that catch memory-safety bugs before attackers do, but most are off until a project opts in. This rule keeps them on and keeps the exceptions honest. The `xcode-security-pro` skill audits a project and plans the rollout.

> **Sources.** Apple's Enhanced Security and bounds-safety documentation and Apple's Xcode 27 security-settings and C bounds-safety agent skills, as published by [Artem Novichkov](https://github.com/artemnovichkov) in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills). Rewritten in this bundle's words.

## Core Rules

- **Enhanced Security on eligible targets.** `ENABLE_ENHANCED_SECURITY = YES` at project level for apps, XPC services, system extensions, and tools, plus `com.apple.security.hardened-process` = `true` and `…enhanced-security-version-string` = `"2"` in the entitlements.
- **Overrides are per target and documented.** `ENABLE_POINTER_AUTHENTICATION = NO` belongs only on a target linking a binary without an arm64e slice. Ask the vendor for arm64e.
- **C-family warnings on**: `GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR`, `GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE`, `CLANG_WARN_IMPLICIT_FALLTHROUGH`, `GCC_WARN_64_TO_32_BIT_CONVERSION`, implicit function declarations as errors. They do nothing for pure Swift.
- **Analyzer checks stay on**, including the default-on Keychain, unchecked-return, and insecure-API checks, and `xcodebuild analyze` runs in CI.
- **Hardware memory safety is staged.** Memory Tagging (`checked-allocations`) in soft mode first; checked pointer arithmetic only on supported hardware.
- **C code adopts `-fbounds-safety` file by file**, headers first, with `<ptrcheck.h>` annotations, never casts that hide the bounds.
- **No silent weakening.** A build broken by a security setting means the code or dependency needs fixing. A deliberate `NO` goes in `docs/xcode-security-settings.md` with the reason and a revisit date.

## Patterns to Follow

```
// Project.xcconfig
ENABLE_ENHANCED_SECURITY = YES
GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR
GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE

// LegacySDKBridge.xcconfig (target-level; see docs/xcode-security-settings.md)
ENABLE_POINTER_AUTHENTICATION = NO
```
