# Security compiler warnings and analyzer checks

> **Sources.** Clang and Xcode build-setting documentation and Apple's Xcode 27 "audit Xcode security settings" agent skill, published by [Artem Novichkov](https://github.com/artemnovichkov) in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills). Rewritten for this bundle. Confirm names with `xcodebuild -showBuildSettings`.

These settings affect C, C++, and Objective-C compilation only. A pure-Swift target gets nothing from them; say so rather than recommending them.

## Recommended warnings

| Setting | Value | Catches |
|---|---|---|
| `GCC_WARN_ABOUT_RETURN_TYPE` | `YES_ERROR` | a non-void function falling off the end (undefined value) |
| `GCC_WARN_UNINITIALIZED_AUTOS` | `YES_AGGRESSIVE` | reads of uninitialized locals |
| `CLANG_WARN_IMPLICIT_FALLTHROUGH` | `YES` | an unannotated `switch` fallthrough |
| `GCC_WARN_64_TO_32_BIT_CONVERSION` | `YES` | silent truncation that becomes a bad length or index |
| `GCC_TREAT_IMPLICIT_FUNCTION_DECLARATIONS_AS_ERRORS` | `YES` | calls to undeclared functions (wrong argument and return types) |

## Recommended analyzer and clang-tidy checks

| Setting | Value | Catches |
|---|---|---|
| `CLANG_ANALYZER_SECURITY_FLOATLOOPCOUNTER` | `YES` | floating-point loop counters |
| `CLANG_ANALYZER_SECURITY_INSECUREAPI_RAND` | `YES` | `rand()` / `random()` where a CSPRNG is needed |
| `CLANG_ANALYZER_SECURITY_INSECUREAPI_STRCPY` | `YES` | `strcpy` / `strcat` |
| `CLANG_TIDY_BUGPRONE_REDUNDANT_BRANCH_CONDITION` | `YES` | branch conditions that can't change |

These analyzer checks are **on by default**; flag any explicit `NO`: Keychain API misuse, unchecked return values, `getpw` / `gets`, `mkstemp`, `vfork`, and printf-style type checking.

## Optional, noisier

Recommend one at a time on code that's already clean, since each can produce many findings on a legacy codebase: `CLANG_WARN_SUSPICIOUS_IMPLICIT_CONVERSION`, `CLANG_ANALYZER_SECURITY_BUFFER_OVERFLOW_EXPERIMENTAL`, `CLANG_WARN_ASSIGN_ENUM`, `GCC_WARN_SIGN_COMPARE`, and the Objective-C ones (`CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF`, `CLANG_WARN_OBJC_REPEATED_USE_OF_WEAK`).

## Where analyzer runs

Analyzer checks only run during **Product ▸ Analyze** or `xcodebuild analyze`. Recommend adding `xcodebuild analyze` (with `CLANG_ANALYZER_OUTPUT=plist-html` for reports) to CI; enabling the settings alone changes nothing in a normal build.

## Review checklist

1. Does the target compile C-family code? If not, skip this file.
2. Recommended warnings set, at project level?
3. Recommended analyzer checks on, default-on checks not disabled?
4. Analyzer run in CI?
