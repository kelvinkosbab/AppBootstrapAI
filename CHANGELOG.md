# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project does not yet cut tagged releases — everything below lives under
`[Unreleased]` and reconstructs the bundle's current capabilities from history.
When the first tag is cut, `[Unreleased]` is promoted to a dated version section.

## [Unreleased]

### Added

- **One-command installer (`install.sh`)** that copies the matching rules,
  skills, settings, `CLAUDE.md` template, and `.gitignore` entries into a
  target repo. Never overwrites an existing `CLAUDE.md`, `settings.json`, or
  agent file — prints what it skipped.
- **Platform auto-detection** — with no `--platform`, the installer sniffs the
  target dir (`Package.swift` / `*.xcodeproj` → apple; `build.gradle*` /
  `gradlew` → android; both → both; neither → both) and prints the matched
  signals. Explicit `--platform` always wins.
- **`--features` categories** with a `recommended` preset (the 9 day-one
  categories) and `all`. Composable CSV (`recommended,ai,spatial`).
- **Multi-agent installs (`--agents`)** — `claude` (default), `copilot`,
  `cursor`, `gemini`, `codex`, or `all`. Generates each agent's native file
  shape (`.github/copilot-instructions.md`, `.cursor/rules/*.mdc`, `GEMINI.md`,
  `AGENTS.md`) from the same rule source. Skills stay Claude-only.
- **`--upgrade`** — a per-file 3-way diff (installed hash vs. current disk vs.
  bundle) that classifies every tracked file as up-to-date / safe-update /
  locally-edited / conflict / orphan / addition / rename, plus the same diff
  for MCP entries. Plan-only by default.
- **`--upgrade --apply`** with `--force-conflicts` (overwrite locally-edited
  files), `--prune` (delete orphans + out-of-scope), and `--migrate-manifest`
  (bring a v1 manifest forward). Surfaces a GitHub compare URL when the bundle
  commit differs.
- **`--uninstall`** with `--force-conflicts`, `--purge` (also remove
  `CLAUDE.md`/`settings.json`), and `--keep-mcps`. Strips the `.gitignore`
  block and the manifest; preserves non-`mcpServers` keys in
  `settings.local.json`.
- **`--with-mcps` + `--list-mcps`** — five curated MCP-server recipes
  (XcodeBuildMCP, Xcode-native, android-mcp-server, Firebase, Sentry) merged
  into `.claude/settings.local.json` with config hashing.
- **`--dry-run`** and **`--list` / `--list --json`** (machine-readable catalog
  consumed by the MCP server).
- **Manifest v2** at `.claude/.appbootstrap-manifest.json` — per-file SHA-256
  hashes, `bundle_commit`, full selection, and `mcps_installed`. Powers the
  upgrade/uninstall flows.
- **`RENAMES.md`** — rule + skill-directory rename tracking honored by
  `--upgrade` so renames show as a single row, not delete + add.
- **Apple rules** — Swift 6.2 strict concurrency, SwiftUI MVVM, Foundation
  Models, accessibility, Objective-C + ObjC accessibility, SPM conventions,
  DocC strategy, testing strategy, localization, **linting** (SwiftLint +
  formatter), **logging** (os.Logger / privacy markers / levels), **visionOS**
  (spatial), and **TestFlight deployment**.
- **Android rules** — coroutines, Compose, Gradle conventions, project rules,
  accessibility, KDoc strategy, testing strategy, localization, **linting**
  (ktlint + detekt + Android Lint), **logging** (Timber / release-stripping /
  crash-reporter integration), and **Play beta deployment**.
- **Cross-platform** — project documentation rule (README/CHANGELOG/ADR).
- **Skills (Apple/Swift)** — `swift-concurrency-pro`, `swift-docc-pro`,
  `swift-error-handling-pro`, `swift-logging-pro`, `swift-package-pro`,
  `swift-testing-pro`, `swiftui-pro`, `coredata-swift6-pro`. **(Android)** —
  `android-gradle-architecture-pro`, `r8-shrink-pro`,
  `xml-to-compose-migration-pro`.
- **`linting`** feature category — in the `recommended` default set (10
  categories). **`spatial`** (visionOS) and **`deployment`** (TestFlight + Play
  beta) feature categories — opt-in, not in `recommended`.
- **MCP server** (`mcp-server/`) wrapping `install.sh` as typed tools:
  `list_categories`, `list_rules`, `list_skills`, `preview_install`,
  `install`, `preview_upgrade`. Reads its category set live from
  `install.sh --list --json`.
- **Templates** — `Package.template.swift` (with a `makeTargets()` helper) and
  three starter `CLAUDE.md` templates (apple / android / cross-platform).
- **Git-workflow guardrails** in `CLAUDE.md` and every template: never commit,
  push, amend, or run destructive git commands without explicit instruction.
- **CI** — `shellcheck`; `frontmatter` (rule/skill validation); a cross-OS
  (Ubuntu + macOS) `install-smoke-test` with 230+ assertions; an `mcp-server`
  workflow (`tsc` build + startup smoke); and a `python` workflow
  (`ruff check --select F` + `py_compile`) covering `lib/*.py` and
  `.github/scripts`.

### Changed

- **`install.sh` modularized** from a ~2,800-line monolith into a ~460-line CLI
  dispatcher plus `lib/` modules: six sourced bash files
  (`predicates.sh`, `detect_platform.sh`, `list_modes.sh`, `install_mode.sh`,
  `install_mcps.sh`, `upgrade_mode.sh`), four Python modules (`upgrade.py`,
  `uninstall.py`, `mcp_merge.py`, `inherit_selection.py`), and `help.txt`.
- **MCP server reads the category set live** from `install.sh --list --json`
  instead of a hand-maintained array, eliminating a drift class.
- **README + GitHub About** reframed to lead with multi-agent support and the
  full Apple/Android coverage including visionOS and deployment.

### Fixed

- CI path filters now cover `lib/**` — the modularization had moved most of the
  installer logic out of the watched paths, silently narrowing shellcheck and
  smoke-test coverage.
- Shellcheck `SC2034` false positives on cross-file globals (the linter doesn't
  follow `source=` directives) silenced with targeted, documented disables.
- Stray `f`-prefix on a placeholder-less string in `lib/upgrade.py`.
