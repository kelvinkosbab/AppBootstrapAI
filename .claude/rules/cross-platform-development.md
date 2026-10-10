---
description: Building one app on Apple and Android at the same time with AI agents — choosing what to share (native×2 vs Kotlin Multiplatform), monorepo layout with nested CLAUDE.md files, spec-first feature work, one shared vocabulary of names across platforms, single sources of truth for API contracts, design tokens, icons, string keys, analytics, flags, and deep links, parity tracking, platform-idiomatic UX, and CI path filters
globs: "**/*.{swift,kt,kts,xml,xcstrings,json,yml,yaml,md}"
---

# Cross-Platform Development (Apple + Android)

Installed with `--platform both`. Two native codebases double the code an agent writes and a reviewer reads, so the efficiency wins come from **sharing decisions, names, and contracts** — not from forcing one codebase onto both platforms. The goal: a feature is specified once, implemented twice by agents that use the same names, verified on both, and drift is caught mechanically. To port a feature, audit parity, or set up the repo, invoke the **`cross-platform-parity-pro`** skill.

## Decide What to Share — Deliberately

| Strategy | Share | When |
|---|---|---|
| **Native × 2** (default) | Specs, contracts, tokens, names | Most apps. Each platform stays idiomatic; every platform rule in this bundle applies as written. |
| **Kotlin Multiplatform (KMP) for logic** | Domain models, repositories, networking, validation | Heavy, identical business logic (sync engines, pricing, offline rules) where two implementations would drift. UI stays SwiftUI + Compose. |
| **Shared UI** (Compose Multiplatform, Flutter, React Native) | Everything | Out of scope for this bundle's rules — they assume native UI. |

- **Make it one decision, recorded in an ADR** (`docs/adr/`, see [`project-documentation.md`](./project-documentation.md)). "We'll share some of it later" produces three half-architectures.
- **KMP shares logic, not UI.** If adopted, the shared module exposes the same repository interfaces the platform rules expect (`apple-repository-pattern.md`, `android-repository-pattern.md`), and the Swift side gets an idiomatic API (async/await, `AsyncSequence`) through an interop layer — not raw `Flow` callbacks. Details in the skill's `references/kmp.md`.
- **Even native × 2 shares a lot**: the API contract, the design tokens, the icon and string vocabularies, the analytics schema, flag keys, and route names. Those are below.

## Repo Layout for Agents

```
MyApp/
├── CLAUDE.md                 # shared: product, parity rules, where things live, how to verify both
├── apple/                    # Xcode project + local SPM package (apple-modular-architecture.md)
│   └── CLAUDE.md             # Apple build/test commands, module graph, gotchas
├── android/                  # Gradle build (android-gradle-conventions.md)
│   └── CLAUDE.md             # Android build/test commands, module graph, gotchas
├── shared/                   # platform-neutral sources of truth
│   ├── api/openapi.yaml
│   ├── design-tokens/        # tokens.json → generated Swift + Kotlin
│   ├── analytics/events.yaml
│   └── strings/              # or: the translation platform is the source
└── docs/
    ├── features/<feature>.md # specs both platforms implement
    └── parity.md             # feature × platform status
```

- **One repo** for both apps when one team ships both — an agent can read the spec, the other platform's implementation, and the shared contracts in one session. Separate repos make "port this from iOS" a copy-paste across clones.
- **Nested `CLAUDE.md` files**: Claude Code loads the root file at session start and a subdirectory's `CLAUDE.md` when it works in that directory. Keep the root short (shared facts, parity rules, verification commands for both); put per-platform build commands and gotchas in `apple/CLAUDE.md` and `android/CLAUDE.md` so an Android task doesn't pay for Xcode context.
- **Install the bundle once at the root** with `--platform both`; the `apple-*` rules glob Swift files and the `android-*` rules glob Kotlin files, so each platform's steering only fires on its own code.

## Spec First, Then Two Implementations

1. **Write the feature spec** (`docs/features/<feature>.md`) before code: user-visible behavior, every screen state (loading / empty / error / content), string keys, icon names, analytics events, deep links, accessibility notes, offline behavior, and acceptance checks. This is the shared input that keeps two agents from inventing two products.
2. **Implement on one platform first** — the *reference* — when the design is still moving; the second implementation then ports settled behavior. **Implement both in parallel** (two sessions, or two subagents in separate `git worktree`s) only once the spec is settled.
3. **Port with the concept map**, not by transliterating code. The other platform's idioms and rules win (see the mapping below and the skill's `references/concept-map.md`).
4. **Verify both** — build and test each platform before calling a cross-platform change done. A shared-contract change (API, tokens, strings) is not done until both platforms regenerate and pass.
5. **Update `docs/parity.md`** in the same change.

**Prompting:** name the platform and the reference explicitly — *"Implement `docs/features/task-list.md` on Android. The Apple version in `apple/…/TaskList/` is the reference for behavior, not for code shape."* Ambiguous prompts in a two-platform repo get the wrong language or both.

## One Vocabulary Across Platforms

The same concept gets the **same name on both sides**, so a reviewer, an agent, or a grep can jump between them:

| Concept | Apple | Android |
|---|---|---|
| Screen state holder | `TaskListViewModel` (`@MainActor @Observable`) | `TaskListViewModel` (`@HiltViewModel`) |
| Screen state | `TaskListViewModel` properties / `TaskListState` | `TaskListUiState` |
| Data access | `protocol TasksRepository` | `interface TasksRepository` |
| Live data | `AsyncSequence` | `Flow` |
| One-shot async | `async throws` | `suspend` |
| Domain model | `struct Task: Sendable` | `data class Task` |
| Icon vocabulary | `AppIcon.delete` | `AppIcons.Delete` |
| Design tokens | `Color.surfaceElevated`, `Spacing.m` | `colorScheme.surfaceContainerHigh`, `AppTheme.spacing.m` |
| String key | `task_list.empty_title` (catalog) | `task_list_empty_title` (`strings.xml`) |
| DI | init injection at `AppCore` | Hilt modules |
| Logging | `Logger.tasks` | `Timber` |

- **Same type names, same file names** where the platform allows (`TaskListViewModel.swift` ↔ `TaskListViewModel.kt`); same module names (`FeatureTasks` ↔ `:feature:tasks`).
- **String keys map mechanically**: one key, `.` → `_` on Android (resource names can't contain dots). Then a script can diff key sets.
- **Icons map by meaning**: `AppIcon` cases and `AppIcons` properties share names; the glyphs differ (SF Symbols vs Material Symbols) and should. See [`apple-iconography.md`](./apple-iconography.md) / [`android-iconography.md`](./android-iconography.md).

## Single Sources of Truth for Shared Contracts

| Contract | Source | Generated / checked |
|---|---|---|
| **HTTP API** | `shared/api/openapi.yaml` | Swift client (swift-openapi-generator) + Kotlin client (openapi-generator); never hand-written DTOs drifting per platform |
| **Design tokens** | `shared/design-tokens/*.json` | Style Dictionary (or a small script) → Swift token file + Compose `Color`/`Dp` objects consumed by each design-system module |
| **Strings** | Translation platform (Lokalise, Crowdin, Phrase) or `shared/strings/` | Exported to `.xcstrings` and `strings.xml`; CI diffs key sets |
| **Analytics events** | `shared/analytics/events.yaml` | Typed event APIs per platform; no string-literal event names at call sites |
| **Feature flags / remote config** | One key list | Typed accessors per platform; same key, same default |
| **Deep links** | Route table in `docs/` | Universal Links (`apple-app-site-association`) + App Links (`assetlinks.json`) on the same domain, same paths |

- **Generated code is not edited by hand** and is excluded from lint and coverage on both sides.
- **A contract change touches both platforms in one PR** (or one PR plus a linked follow-up the parity file records) — never "Android will catch up."

## Parity Is Behavior, Not Pixels

- **Same behavior, platform-native presentation.** Navigation, back behavior, sheets vs bottom sheets, typography, haptics, and system components follow the HIG on Apple and Material 3 on Android. A Material-style FAB on iOS or an iOS-style swipe-back hack on Android is a bug, not parity.
- **Platform-only features are fine and declared** — widgets, Live Activities, App Intents, Wear/TV, Quick Settings tiles — marked "Apple only" / "Android only" in `docs/parity.md` rather than silently missing.
- **Accessibility parity**: VoiceOver and TalkBack both reach every action; Dynamic Type and font scale both reflow. Each platform's accessibility rule still applies.

## Tracking Drift

- **`docs/parity.md`**: a feature × platform table (`✅ shipped`, `🚧 in progress`, `⏳ planned`, `— n/a`) plus intentional differences. Updated in the PR that changes status.
- **PR template checkbox**: "Other platform: done in this PR / follow-up #___ / not applicable (why)".
- **Mechanical checks in CI** where cheap: string-key diff, icon-vocabulary diff, analytics-event diff (the skill's `references/parity-audit.md` has the scripts).

## CI

- **Path-filtered workflows**: `apple/**` runs Apple jobs on macOS runners, `android/**` runs Android jobs on Linux; **`shared/**` runs both**. macOS minutes cost more — don't run Xcode builds for an Android-only change.
- **Both must be green** for a change under `shared/` or `docs/features/` to merge.
- Release pipelines stay per platform ([`apple-testflight-deployment.md`](./apple-testflight-deployment.md), [`android-play-beta-deployment.md`](./android-play-beta-deployment.md)); versioning can be shared (same marketing version) but build numbers are each platform's own monotonic counter.

## Common Pitfalls

- **Transliterating code** — Swift `class` hierarchies ported line-for-line into Kotlin (or `Flow` callbacks forced into Swift). Port behavior; write each side idiomatically.
- **Two names for one thing** (`ItemsStore` on iOS, `ProductRepository` on Android) — every cross-platform conversation and grep pays for it.
- **Hand-written DTOs per platform** for the same API — they drift on the first nullable field.
- **Copy-pasted tokens** (hex values in two places) — the rebrand lands on one platform.
- **Unspecified features** — two agents fill gaps differently; the spec is cheaper than reconciling.
- **One giant root `CLAUDE.md`** with both platforms' build details — every session loads context it doesn't need.
- **Ambiguous prompts** ("add the setting") in a two-platform repo.
- **Shared-UI frameworks adopted per feature** — a Compose Multiplatform screen inside a SwiftUI app without an architectural decision behind it.
- **Silent platform gaps** — a feature missing on one side with no parity entry.
