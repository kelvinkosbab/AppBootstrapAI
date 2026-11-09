---
description: SwiftLint + formatter (swift-format / SwiftFormat) strategy for Apple projects — config structure, opt-in and analyzer rules, suppression hygiene, where it runs, incremental adoption, version pinning
globs: "**/{*.swift,.swiftlint.yml,.swiftlint.yaml,.swift-format,.swiftformat}"
paths:
  - "**/{*.swift,.swiftlint.yml,.swiftlint.yaml,.swift-format,.swiftformat}"
must:
  - "Use one formatter (SwiftFormat or swift-format) and turn off SwiftLint's overlapping formatting rules."
  - "Enable `force_unwrapping` and other high-value opt-in rules; run `--strict` in CI with a pinned version."
  - "Suppress with `swiftlint:disable:next <rule>` and a reason; never blanket-disable."
  - "When a rule fires, fix the code first; tune or suppress only with a stated reason."
---

# Apple Linting Strategy

The must-follow rules for SwiftLint and a Swift formatter. Config examples, the opt-in rule list, analyzer setup, and the backlog tiers are in [`linting-pro/references/swiftlint.md`](../skills/linting-pro/references/swiftlint.md); read the matching section only when a line below isn't enough. Review or adopt with `linting-pro`.

## Tools

- **A formatter owns layout; SwiftLint owns everything else.** Pick one formatter, SwiftFormat (`.swiftformat`) or Apple's swift-format (`.swift-format`), never both, and disable SwiftLint's overlapping formatting rules.
- **Pin every tool's version** (SPM plugin, Mint, or Homebrew formula). An unpinned upgrade turns CI red with no code change.

## `.swiftlint.yml`

- **Turn on the high-value `opt_in_rules`**: `force_unwrapping` first, then `empty_count`, `first_where`, `contains_over_filter_count`, `redundant_nil_coalescing`, `sorted_imports`.
- **`excluded:` generated and vendored code** (`.build`, `**/*.generated.swift`, `Pods`, `DerivedData`).
- **Tune thresholds instead of disabling rules** (`line_length`, `type_body_length`, `identifier_name`).
- **Analyzer rules** (`unused_import`, `unused_declaration`) run through `swiftlint analyze` with a fresh compiler log, in CI only.

## Suppression

- **Smallest scope, with a reason**: `// swiftlint:disable:next <rule>` plus a trailing comment.
- A region `disable` always has a matching `enable`. Never `// swiftlint:disable all`; move the file to `excluded:` instead.

## When a rule fires

1. **Fix the code.** The default.
2. **Tune the rule** once in `.swiftlint.yml` when its threshold is wrong for the project.
3. **Suppress at the call site** when this one instance is a justified exception.
4. **Disable project-wide** only when the rule is wrong for the whole codebase, with a comment saying why.

Never jump to step 4 to clear one finding, and don't use `disabled_rules:` as a backlog. Correctness rules (`force_unwrapping`, `force_cast`, `force_try`) are `error`; style rules start as `warning` and become `error` once clean.

## Where it runs

- **CI is the gate**: `swiftlint lint --strict`, plus the analyzer.
- Locally, an SPM build-tool plugin or Xcode Run Script phase (guarded with `command -v swiftlint`) may warn but shouldn't fail builds. Never run the analyzer in the build phase.
- **Legacy code**: exclude what you can't fix yet, get the default rules to zero, then add `opt_in_rules` a batch at a time.
