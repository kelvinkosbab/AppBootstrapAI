---
description: ktlint + detekt + Android Lint strategy for Android projects — distinct jobs of each tool, .editorconfig / detekt.yml / lint.xml config, baselines, suppression hygiene, CI placement, version pinning
globs: "**/{*.kt,*.kts,.editorconfig,detekt.yml,detekt-baseline.xml,lint.xml,lint-baseline.xml,build.gradle.kts,build.gradle}"
paths:
  - "**/{*.kt,*.kts,.editorconfig,detekt.yml,detekt-baseline.xml,lint.xml,lint-baseline.xml,build.gradle.kts,build.gradle}"
must:
  - "Run ktlint, detekt, and Android Lint (`lintDebug`) as blocking CI checks; each covers different problems."
  - "Never regenerate a lint or detekt baseline to make CI pass."
  - "Suppress only the smallest element, with a reason; never `@file:Suppress` as a shortcut."
  - "When a rule fires, fix the code first; tune or suppress only with a stated reason."
---

# Android Linting Strategy

The must-follow rules for ktlint, detekt, and Android Lint. Config examples (`.editorconfig`, `detekt.yml`, `lint {}`), baseline setup, and the backlog tiers are in [`linting-pro/references/android-lint-tools.md`](../skills/linting-pro/references/android-lint-tools.md); read the matching section only when a line below isn't enough. Review or adopt with `linting-pro`.

## Three tools, three jobs

- **ktlint** formats and enforces Kotlin style (`ktlintFormat` locally, `ktlintCheck` in CI). Set `ktlint_code_style = android_studio` and disable `function-naming` for `@Composable` PascalCase.
- **detekt** finds complexity, smells, and likely bugs. Use `buildUponDefaultConfig = true` and override thresholds; run the type-resolution tasks (`detektMain` / `detektTest`) in CI. Don't enable detekt's `formatting` ruleset alongside standalone ktlint.
- **Android Lint** checks resources, manifest, API levels, accessibility, and security. Run `lintDebug` (or `lint`), not only `lintRelease`; set `checkDependencies = true` in the app module and `warningsAsErrors = true` in CI. Keep `abortOnError` on.
- **Pin all three** in `gradle/libs.versions.toml`.

## Baselines

- `detekt-baseline.xml` and `lint-baseline.xml` are a debt ledger for legacy code: generate once, then shrink them every release.
- **Never regenerate a baseline to make CI pass.** That accepts the new issue too.

## Suppression

- **Smallest element, with a reason**: `@Suppress("RuleId")` / `@SuppressLint("CheckId")` on the function or property, `tools:ignore` in XML.
- Never `@file:Suppress(...)`; it hides future violations too.

## When a rule fires

1. **Fix the code.** The default.
2. **Tune the rule** once (`detekt.yml` thresholds, `lint.xml` severity) when its threshold is wrong for the project.
3. **Suppress at the call site** when this one instance is a justified exception.
4. **Disable project-wide** only when the rule is wrong for the whole codebase (like `function-naming` versus Compose), with a comment.

Correctness and security findings (`MissingPermission`, `StopShip`, exported components, detekt `potential-bugs`) are `error`. Formatting is ktlint's and needs no backlog.

## CI

- Run `ktlintCheck`, `detekt`, and `lintDebug` as blocking checks. Many projects forget Android Lint and ship bugs the other two can't see.
