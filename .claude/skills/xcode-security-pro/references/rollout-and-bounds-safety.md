# Phased rollout, the decision record, and C bounds safety

> **Sources.** Apple's `-fbounds-safety` and Clang SafeBuffers documentation and Apple's Xcode 27 security-settings and "adopt C bounds safety" agent skills, published by [Artem Novichkov](https://github.com/artemnovichkov) in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills). Rewritten for this bundle.

## Adopt in phases

Each phase is one change the team can test and ship before the next.

1. **Compile-time**: the warnings and analyzer checks in `settings-reference.md`, stack zero-initialization (`CLANG_ENABLE_STACK_ZERO_INIT = YES`), and read-only platform memory (the `dyld-ro` entitlement). Well-behaved code sees no change; code that writes to `const` data will crash and needs fixing. Pure-Swift targets also take phase 2's runtime restrictions.
2. **Runtime restrictions**: Enhanced Security with the default entitlements (hardened heap, dyld read-only, platform restrictions) and typed allocators.
3. **Pointer authentication and C++ hardening**: confirm every binary dependency has arm64e and run the full test suite on device.
4. **Hardware memory safety**: MTE in soft mode, then enforced; then checked pointer arithmetic where hardware allows.

## The decision record

Keep `docs/xcode-security-settings.md` (or the project's ADR folder): one row per setting or entitlement left off or overridden, with the target, the reason (a dependency, a hardware floor, a known false-positive rate), and when to revisit. Audits read it before flagging, so a deliberate `NO` isn't re-raised every time.

## C bounds safety (`-fbounds-safety`)

Bounds safety makes the compiler check pointer arithmetic and indexing in C against bounds it learns from annotations, and trap on overflow.

- `ENABLE_C_BOUNDS_SAFETY = YES` applies to **C files only** (not Objective-C, not C++). For incremental adoption, add `-fbounds-safety` per file in Build Phases ▸ Compile Sources instead.
- **Headers first**: annotate the public headers a file uses, then the file. Include `<ptrcheck.h>`.
- Annotations: `__counted_by(n)` (n elements), `__sized_by(n)` (n bytes), `__ended_by(end)`, `__null_terminated` (strings), and the pointer kinds `__single` (one object, no arithmetic), `__indexable`, `__bidi_indexable` (the default for locals).
- Build with `-ferror-limit=0` while annotating so you see every error at once. Fix by adding annotations, not by casting them away.
- `CLANG_BOUNDS_SAFETY_SOFT_TRAPS = call-minimal` reports instead of crashing during rollout; `-fbounds-safety-unique-traps` gives each check its own trap so crash reports point at the line.
- C++ gets the equivalent through `ENABLE_CPLUSPLUS_BOUNDS_SAFE_BUFFERS` (Clang's SafeBuffers: `-Wunsafe-buffer-usage` plus hardened `std::span` and containers).

## Review checklist

1. Next phase proposed, not all four at once?
2. Decision record exists and covers every disabled setting?
3. C files adopting bounds safety have annotated headers, and casts aren't used to silence errors?
4. Soft traps used during rollout and removed before calling it done?
