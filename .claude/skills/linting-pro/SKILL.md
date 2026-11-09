---
name: linting-pro
description: Sets up, adopts, and reviews linting and formatting for Apple and Android projects — SwiftLint with SwiftFormat or swift-format, and ktlint, detekt, and Android Lint — including config files, opt-in and analyzer rules, baselines, suppression hygiene, finding triage, and CI gates. Use when adding a linter, turning one on in a legacy codebase, a rule fires and you're unsure whether to fix, tune, or suppress, or CI lint results are noisy or flaky.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
---

Make lint findings worth reading: one formatter owns layout, the linters catch real bugs, and CI blocks on them. This is the deep companion to the always-on `apple-linting-strategy.md` and `android-linting-strategy.md` rules. Report only genuine problems.

Pick the mode from the request:

- **Set up**: no linter yet. Write the config from the reference for the platform in scope and wire the CI step.
- **Adopt on legacy code**: a first run floods with findings. Exclude generated code, get the default rules to zero, then add opt-in rules (Apple) or burn down a baseline (Android) in batches.
- **Review**: audit the existing config, suppressions, and CI wiring against the checklist below.

Load only the reference for the platform in scope:

- `references/swiftlint.md` — SwiftLint `.swiftlint.yml` structure, the opt-in and analyzer rules, suppression forms, triage tiers, where SwiftLint runs, incremental adoption, and SwiftFormat versus swift-format.
- `references/android-lint-tools.md` — `.editorconfig` for ktlint, `detekt.yml` and type resolution, the Android Lint `lint {}` block and `lint.xml`, baselines, suppression, triage tiers, and CI placement.

## Review Checklist

1. **One formatter.** Exactly one tool rewrites layout; the linter's overlapping formatting rules (SwiftLint layout rules, detekt `formatting`) are off.
2. **Pinned versions** for every lint tool, in the SPM plugin, Mint, Gemfile, or `libs.versions.toml`.
3. **High-value checks on**: SwiftLint `force_unwrapping` and the analyzer rules; detekt type resolution; Android Lint `lintDebug` with `checkDependencies`.
4. **Generated and vendored code excluded.**
5. **Suppressions are scoped and explained**: no `swiftlint:disable all`, no unpaired region `disable`, no `@file:Suppress`, every suppression has a reason.
6. **Baselines shrink**: `detekt-baseline.xml` and `lint-baseline.xml` aren't regenerated in the same PR that adds code.
7. **CI is the gate**: `swiftlint --strict` or `ktlintCheck` + `detekt` + `lintDebug`, blocking; correctness rules at `error`.

## Triage Order

For each finding: fix the code, else tune the rule's threshold once, else suppress the one instance with a reason, else (rarely) disable the rule project-wide with a comment. A finding cleared by a step further down the list than it needed is itself a finding.

## Output Format

Group findings by severity: **blocking** (CI not gating, unpinned tools, regenerated baselines, blanket suppressions), **degraded** (missing high-value rules, two formatters, analyzer not run), **polish** (threshold tuning, rule ordering). Give each as file:line, the problem, and the fix with the config or code change. End with the count per severity and the first three fixes.
