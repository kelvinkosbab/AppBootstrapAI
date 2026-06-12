# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org).
The `1.0.0` section reconstructs the bundle's capabilities from pre-tag history.

## [Unreleased]

### Added

- **`concise-comments-and-commits.md`** (core, cross-platform) — fires on all
  Swift/Kotlin/ObjC source. Comments default to none (why-not-what, no diff
  commentary or narration); commit messages get a short imperative subject and
  a body only when the why isn't visible in the diff. Targets the verbosity AI
  assistants produce that stops teammates reading either.

## [1.0.0] - 2026-06-11

### Added

- **`android-ai-best-practices.md`** — the `ai` category is now cross-platform.
  The Android counterpart to the Apple Foundation Models rule: on-device Gemini
  Nano via ML Kit GenAI / AICore vs cloud Gemini via Firebase AI Logic, never
  ship a raw model API key (App Check / backend proxy), two-level availability
  gating, streaming into Compose with placeholder-then-mutate, structural
  cancellation, interface + fake testability, consent + Data-safety hooks.
  Previously `--platform android --features ai` installed nothing.
- **`swiftdata-pro` skill** (persistence) — Paul Hudson's MIT
  [`swiftdata-agent-skill`](https://github.com/twostraws/swiftdata-agent-skill),
  bundled alongside `coredata-swift6-pro`: core model/context rules, safe
  `#Predicate` usage, CloudKit constraints, iOS 18+ indexing, iOS 26+ class
  inheritance.
- **`android-compose-pro` skill** (ui) — deep Compose review: recomposition
  stability + skippability (strong-skipping aware), side-effect audit
  (`LaunchedEffect` keys, `rememberUpdatedState`, `DisposableEffect` teardown),
  lazy-list performance (keys, `contentType`, `derivedStateOf`), state modeling.
- **`android-coroutines-pro` skill** (concurrency) — deep coroutines/Flow
  review: scope-to-lifecycle mapping, cooperative cancellation
  (`CancellationException` / `runCatching` traps), `launch` vs `async`
  exception propagation, supervisor boundaries, `stateIn`/`shareIn`
  configuration, `callbackFlow` teardown, coroutine testing (virtual time,
  Turbine). Android skill parity: 5 Android skills alongside 9 Apple.
- **Privacy-manifest / Data-safety guidance in the deployment rules** —
  `apple-testflight-deployment.md` gains a `PrivacyInfo.xcprivacy` section
  (required-reason APIs, collected-data types, tracking domains, third-party
  SDK manifests, ITMS-91053/91061 — the upload gate AI-generated code trips
  most often); `android-play-beta-deployment.md` gains the Play Data safety
  form discipline (SDK-sourced data, mismatch enforcement, AI-SDK triggers).

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
- **`--apple-platforms` selector** — CSV of `ios,macos,tvos,watchos,visionos`
  (or `all`); default `ios,macos,tvos,watchos` (every Apple platform except
  visionOS, the lean default for typical app projects). Only the visionOS rule
  is sub-platform-specific today, so the selector stays in sync with the
  `spatial` feature category (naming `visionos` ⇔ installing the visionOS rule;
  `--features …,spatial` remains the equivalent older form). Recorded in the
  manifest (`apple_platforms_input` / `_resolved`) and inherited on `--upgrade`.
  A forward-looking framework for future platform-specific rules.
- **`--android-platforms` selector** — CSV of `phone,tablet,wear,tv,auto` (or
  `all`); default `phone,tablet`. The Android counterpart to `--apple-platforms`,
  but purely a forward-looking framework: **no Android rule is form-factor-specific
  today**, so it doesn't change what installs — it's validated, recorded in the
  manifest (`android_platforms_input` / `_resolved`), inherited on `--upgrade`,
  and surfaced in `--list`/`--json`. A Wear OS / Android TV / Auto rule would gate
  by these tokens.
- **Multi-agent installs (`--agents`)** — `claude` (default), `copilot`,
  `cursor`, `gemini`, `codex`, `kiro`, or `all`. Generates each agent's native
  file shape (`.github/copilot-instructions.md`, `.cursor/rules/*.mdc`,
  `GEMINI.md`, `AGENTS.md`, `.kiro/steering/*.md`) from the same rule source.
  Skills stay Claude-only.
- **Amazon Kiro support (`--agents kiro`)** — writes per-rule
  [steering files](https://kiro.dev/docs/steering/) to `.kiro/steering/<name>.md`,
  rewriting each rule's `globs` frontmatter into Kiro's
  `inclusion: fileMatch` + `fileMatchPattern` (single glob, or an inline array
  for multi-pattern rules) so a rule only enters Kiro's context when a matching
  file is open. Generation is shared between install and the upgrade overlay, so
  the 3-way diff round-trips; `--upgrade`/`--uninstall` track it like any other
  agent file.
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
- **Guided setup (`-i` / `--interactive`)** — a prompt-driven flow that detects
  whether you're creating a new project, adopting into an existing repo, or
  updating an existing install, then walks through platform / Apple-language /
  features / agents / MCP recipes with sensible defaults. Reads answers at a TTY
  or from piped stdin (Enter accepts each default), prints a plan, and confirms
  before writing.
- **`--new`** — create the target directory (and parents) and `git init` a fresh
  repo before installing, for green-field projects. Light scaffolding only — it
  doesn't generate an Xcode/Gradle project.
- **Managed-target guard** — running plain `install` over a directory that
  already has an AppBootstrapAI install now refuses with guidance to use
  `--upgrade` (which preserves the manifest baseline), instead of silently
  resetting it. Pass **`--force`** to deliberately re-install over a managed
  target.
- **`AGENTS.md`** at the repo root — a terse, machine-first guide for AI agents
  *operating* AppBootstrapAI (the recommend → preview → run workflow, the verb
  table, the create/adopt/upgrade situations, and the guardrails). Distinct from
  the `AGENTS.md` the installer writes into target repos.
- **`recommend` command** — `install.sh recommend <dir> [--json]` analyzes a
  directory (read-only) and prints the exact create / adopt / upgrade command to
  run, with rationale. Detects managed-state (manifest present → upgrade),
  platform + signals, Apple-language (`.m`/`.mm`/`.h` scan), and framework usage
  → feature categories (`import FoundationModels` → `ai`; Core Data / SwiftData
  → `persistence`; Room → `persistence`; R8/ProGuard → `shrinking`; XML layouts
  / Fragments → `migration`; fastlane / CI → `deployment`). `--json` emits a
  machine-readable object with a ready-to-exec `command` array — built so an AI
  agent gets the right action in one call instead of grepping the tree.
- **Subcommand verbs** — `install.sh` now accepts a leading command verb
  (`install` / `recommend` / `upgrade` / `uninstall` / `list` / `list-mcps` /
  `setup` / `help`), so `install.sh upgrade .` reads correctly instead of
  `install.sh . --upgrade`. Backward-compatible: every verb has a `--flag`
  alias and the bare `install` verb is optional, so existing scripts, the MCP
  server, and CI keep working unchanged. The file name stays `install.sh`.
- **Manifest v2** at `.claude/.appbootstrap-manifest.json` — per-file SHA-256
  hashes, `bundle_commit`, full selection, and `mcps_installed`. Powers the
  upgrade/uninstall flows.
- **`RENAMES.md`** — rule + skill-directory rename tracking honored by
  `--upgrade` so renames show as a single row, not delete + add.
- **Apple rules** — Swift 6.4 strict concurrency, SwiftUI MVVM, Foundation
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
- **MCP server** (`mcp-server/`) wrapping `install.sh` as nine typed tools:
  `recommend_setup` (analyze a dir → suggested command, the agent's entry point),
  `list_categories`, `list_rules`, `list_skills`, `preview_install`, `install`,
  `preview_upgrade`, `preview_uninstall`, `uninstall`. Reads its category set
  live from `install.sh --list --json`.
- **Templates** — `Package.template.swift` (with a `makeTargets()` helper) and
  three starter `CLAUDE.md` templates (apple / android / cross-platform).
- **Git-workflow guardrails** in `CLAUDE.md` and every template: never commit,
  push, amend, or run destructive git commands without explicit instruction.
- **CI** — `shellcheck`; `frontmatter` (rule/skill validation); a cross-OS
  (Ubuntu + macOS) `install-smoke-test` with 250+ assertions; an `mcp-server`
  workflow (`tsc` build + startup smoke); and a `python` workflow
  (`ruff check --select F` + `py_compile`) covering `lib/*.py` and
  `.github/scripts`.

### Changed

- **Apple rules refreshed for Xcode 27 / Swift 6.4.** Version labels bumped from
  Swift 6.2 → 6.4 (language mode stays `.v6` — unchanged since 6.0); testing
  strategy gains `swift test --repeat-until` flaky-test hunting + the new
  XCTest ↔ Swift Testing interop warning; TestFlight deployment notes the
  Apple-silicon-only toolchain (macOS Tahoe 26.4), the `x86_64`/`ARCHS_STANDARD`
  drop at deployment target ≥ 27, and the `ld64`/`-ld_classic` removal (also a
  new SPM `unsafeFlags` caveat). Skill feature-attribution stays at 6.2 (those
  features shipped in 6.2).
- **Foundation Models modernized for the 2026 SDKs** — the rule now covers the
  pluggable-model surface (`LanguageModel` protocol; `SystemLanguageModel`
  on-device; `PrivateCloudComputeLanguageModel`; `LanguageModelExecutor` to
  bridge external providers like Claude/Gemini), image input
  (`Attachment` / `ImageAttachmentContent` / `ImageReference`), the Foundation
  Models Instrument, and `LanguageModelError`. New symbols are flagged **Beta /
  verify against the iOS 27 SDK**; the stable lifecycle/streaming patterns are
  unchanged.
- **README Apple MCP tooling refreshed** for Xcode 27's native Xcode MCP server
  (debug tools, Preview Snapshot, simulator control), `lldb-mcp`, and **agent
  plug-ins** (skills / MCP / ACP / slash commands) — superseding the Xcode 26.3
  `mcpbridge` framing.
- **Localization rule** notes Xcode 27's `NSLocalizedString`-from-headers
  extraction, the "do not translate" / `translate="no"` convention, and String
  Catalog "Generate Translations" (draft-only; review before shipping).
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
