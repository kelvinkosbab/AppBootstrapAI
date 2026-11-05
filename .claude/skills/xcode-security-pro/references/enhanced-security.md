# Enhanced Security

> **Sources.** Apple's Enhanced Security, pointer authentication, and Memory Integrity Enforcement documentation and Apple's Xcode 27 "audit Xcode security settings" agent skill, published by [Artem Novichkov](https://github.com/artemnovichkov) in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills). Rewritten for this bundle. Verify setting and entitlement names against your Xcode.

## The umbrella setting

`ENABLE_ENHANCED_SECURITY = YES`, set at **project** level, turns on a bundle of protections:

- `ENABLE_POINTER_AUTHENTICATION` (builds an arm64e slice; the simulator drops it automatically),
- `GCC_WARN_SHADOW`, `CLANG_WARN_EMPTY_BODY`, `ENABLE_SECURITY_COMPILER_WARNINGS`,
- `CLANG_CXX_STANDARD_LIBRARY_HARDENING` (`fast` in Release, `debug` in Debug),
- typed allocator support (type-segregated heap allocations).

## Who it applies to

- **Full support** (build settings plus entitlements): application, on-demand install-capable app, XPC service, system extension, command-line tool.
- **Build settings only**: driver extension.
- **Libraries and frameworks** get pointer authentication and ship a universal arm64 + arm64e binary. Watch `ONLY_ACTIVE_ARCH`: a Debug build with it on produces one slice, which can hide a link failure until Release.
- **Binary dependencies without an arm64e slice** fail to link. Override `ENABLE_POINTER_AUTHENTICATION = NO` (and the checked-pointer-arithmetic slice setting) only on the **target** that links them, record why, and ask the vendor for an arm64e build.

## Entitlements

| Entitlement | Value | Default | Notes |
|---|---|---|---|
| `com.apple.security.hardened-process` | `true` | required | turns on runtime hardening |
| `com.apple.security.hardened-process.enhanced-security-version-string` | `"2"` | required | the feature level |
| `…hardened-process.hardened-heap` | `true` | on | hardened allocator |
| `…hardened-process.dyld-ro` | `true` | on | read-only dyld state |
| `…hardened-process.platform-restrictions-string` | `"2"` | on | runtime restrictions |
| `…hardened-process.checked-allocations` | `true` | off | Memory Tagging (MTE); start in soft mode; needs A19 / M5 / S11 or later |
| `…hardened-process.enforce-checked-pointer-arithmetic-overflow` | `true` | off | checked pointer arithmetic; needs `ENABLE_HARDWARE_CHECKED_POINTER_ARITHMETIC_SLICE = YES` on the target (arm64e.x1 slice), MTE, and A20 Pro / S11; no soft mode |

Default-off features trap on violations. Turn them on only after testing on supported hardware, and soak MTE in soft mode (reports without crashing) before enforcing.

## Review checklist

1. Enhanced Security enabled at project level for every eligible target?
2. Required entitlements present with the right values?
3. Every `NO` override target-level, tied to a named binary dependency, and recorded?
4. Release builds produce arm64e for libraries (no `ONLY_ACTIVE_ARCH` in Release)?
5. MTE and checked pointer arithmetic left off until tested on supported hardware?
