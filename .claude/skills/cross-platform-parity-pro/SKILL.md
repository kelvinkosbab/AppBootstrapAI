---
name: cross-platform-parity-pro
description: Ports features between an app's Apple (Swift/SwiftUI) and Android (Kotlin/Compose) codebases, audits the two for drift (strings, icons, analytics events, flags, deep links, behavior), and sets up a monorepo for building both at once with AI agents — nested CLAUDE.md files, shared contracts, parity tracking, per-platform subagents, CI path filters, and the native-vs-Kotlin-Multiplatform decision. Use when a project ships on both Apple platforms and Android, when porting a feature from one platform to the other, or when the two apps have drifted apart.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "Android app architecture guide, Swift API Design Guidelines, Apple HIG and Material 3 platform conventions, Kotlin Multiplatform docs, Claude Code memory (nested CLAUDE.md) and subagent docs"
---

Help one team ship the same app on Apple platforms and Android with AI agents doing much of the writing. This is the deep companion to the always-on `cross-platform-development.md` rule — the rule steers day-to-day work; this skill ports features, audits drift, and sets up the repo. Platform-specific correctness is still owned by the platform rules and skills (`apple-*` / `swift-*`, `android-*`); this skill makes the two sides agree.

Pick the mode from the request:

- **Port** — implement a feature that exists on one platform on the other. Follow `references/porting-workflow.md`; translate idioms with `references/concept-map.md`. Write the code directly.
- **Audit** — compare the two codebases for drift. Run the checks in `references/parity-audit.md` and report gaps by severity.
- **Set up** — a new two-platform repo, or an existing pair of apps being brought together: layout, nested `CLAUDE.md` files, shared contracts, parity file, per-platform subagents, CI. Use `references/repo-setup.md`; if sharing logic via Kotlin Multiplatform is on the table, `references/kmp.md`.

If doing a partial task, load only the relevant reference files.

## Core Instructions

- **Port behavior, not code.** Read the reference implementation to learn *what it does* — states, edge cases, strings, events — then write the target side as a native developer on that platform would. Line-by-line transliteration (Swift class hierarchies in Kotlin, Kotlin `Flow` plumbing in Swift) is the most common failure.
- **The target platform's rules win.** A port into Android follows `android-mvvm-architecture.md`, `android-compose-best-practices.md`, and friends; a port into Apple follows `apple-swiftui-mvvm.md`, `apple-swift6-strict-concurrency.md`, and friends. Where platform conventions differ (navigation, sheets, back behavior, typography), use the target's.
- **Same names, mechanically mappable.** Types, files, modules, string keys, icon vocabulary entries, analytics events, and flag keys use the same names on both sides (casing per language). Renames are flagged, not silently accepted.
- **Shared contracts are generated, not copied.** API clients, design tokens, and event APIs come from the shared source; a hand-written duplicate on one side is a finding.
- **Specs before ports.** If no spec exists for the feature, write `docs/features/<feature>.md` from the reference implementation first (states, strings, events, links, accessibility, acceptance checks) — it becomes the checklist for the port and for review.
- **Verify both sides.** Build and run tests on the target platform after a port; after any shared-contract change, regenerate and build both. Say which commands ran and what passed; never claim parity you didn't check.
- **Severity by user impact**: broken (feature missing or wrong on one platform with no parity note, a contract mismatch that crashes or drops data, untranslated or missing strings, a deep link that opens on one platform only) > drift (renamed concepts, hand-written duplicate DTOs/tokens, differing event names or flag defaults) > polish (naming nits, structure that could mirror more closely).
- Cross-reference, don't duplicate: design-system specifics go to `swift-design-system-pro` / `android-design-system-pro`; Swift concurrency to `swift-concurrency-pro`; coroutines to `android-coroutines-pro`; Gradle multi-module structure to `android-gradle-architecture-pro`; SPM structure to `swift-package-pro`.

## Output Format

**Port mode:** the spec used (or written), then files created/changed on the target platform (path → purpose), the concept mappings applied where they weren't obvious, intentional platform differences, the verification commands run with results, and the `docs/parity.md` line updated.

**Audit mode:** a parity table (feature or contract × Apple × Android × status), then findings grouped by severity. For each: what differs, where (file:line on each side), the user impact, and the fix (which side changes, or which shared source to add). End with the mechanical-check results (string keys, icons, events, flags, links — counts only on one side) and the first three fixes.

**Set-up mode:** the files created (path → purpose), the sharing decision and the ADR that records it, the generation commands for each shared contract, and the CI path filters.

Example audit finding:

### Analytics: `task_completed`

**Broken — Android sends `taskComplete` with no `source` property; Apple sends `task_completed` with `source`. Dashboards undercount Android by the whole event.**

- Apple: `apple/Packages/FeatureTasks/Sources/TaskListViewModel.swift:88` — `analytics.track(.taskCompleted(source: .list))`
- Android: `android/feature/tasks/src/main/kotlin/…/TaskListViewModel.kt:61` — `analytics.log("taskComplete")`
- Fix: generate the Android event API from `shared/analytics/events.yaml` and replace the string literal with `Events.taskCompleted(source = Source.List)`.

End of example.

## References

- `references/concept-map.md` — Swift ↔ Kotlin and SwiftUI ↔ Compose translation table: language features, concurrency, state and view models, navigation, DI, persistence, networking, resources, accessibility, testing, logging.
- `references/porting-workflow.md` — step-by-step port of one feature: spec, reference reading, target skeleton, states, strings/icons/events, platform-native presentation, tests, verification, parity update; plus parallel two-agent work with worktrees.
- `references/parity-audit.md` — scripts that diff string keys, icon vocabularies, analytics events, flag keys, and deep-link routes between the two codebases; the behavioral audit checklist; the parity file format.
- `references/repo-setup.md` — monorepo layout, root and nested `CLAUDE.md` templates, per-platform subagents in `.claude/agents/`, shared-contract generation (OpenAPI, design tokens, analytics), the parity file and PR template, CI path filters, installing this bundle with `--platform both`.
- `references/kmp.md` — when Kotlin Multiplatform pays off, what to share (domain, data, networking) and what not (UI, platform services), module shape, exposing an idiomatic Swift API, testing, and adoption steps.
