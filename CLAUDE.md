# CLAUDE.md

## Project Overview

**AppBootstrapAI** is a drop-in bundle of Claude Code skills and AI steering rules for bootstrapping new app projects. Primary focus is Apple platforms (iOS, macOS, tvOS, watchOS, visionOS) with Swift 6.2 concurrency, SwiftUI, and Swift Testing guidance. Secondary focus is Android (Kotlin, Jetpack Compose, MVVM, Hilt) — rules only for now, no dedicated skills yet.

This repo is **not** a Swift package. It is a collection of `.claude/` assets intended to be copied (or referenced) into a target app repository so that Claude Code picks up consistent review, testing, and style guidance across projects.

## What's in the box

```
.claude/
├── rules/                         # Always-loaded AI steering (Cursor-style rule files)
│   ├── android-accessibility-best-practices.md    # Android: TalkBack / Compose semantics
│   ├── android-project-rules.md                   # Android: Kotlin/Compose/MVVM/Hilt
│   ├── apple-accessibility-best-practices.md      # Apple: SwiftUI a11y
│   └── apple-swift6-strict-concurrency.md         # Apple: Swift 6.2 strict concurrency
├── skills/                        # On-demand Claude Code skills (Apple-only today)
│   ├── swift-concurrency-pro/     # Reviews Swift concurrency correctness
│   ├── swift-testing-pro/         # Writes/reviews Swift Testing code
│   └── swiftui-pro/               # Reviews SwiftUI for modern APIs and a11y
└── settings.json                  # Baseline Claude Code permissions (git, xcodebuild, gradlew, etc.)
```

Plus, at the repo root:

- `install.sh` — one-command bootstrap into any target repo (`--platform apple|android|both`).
- `templates/CLAUDE.template.md` — starter `CLAUDE.md` for the target app, with placeholders.

Each skill ships with:

- `SKILL.md` — the skill's entry point and review checklist (loaded when the skill is invoked).
- `references/` — topic-specific deep-dive notes the skill loads on demand.
- `agents/openai.yaml` — interface metadata (display name, icon, default prompt).
- `assets/` — SVG/PNG icons for the skill.

## How to onboard this into a new app project

Use the installer from the target repo:

```bash
# From the root of your new app repo
/path/to/AppBootstrapAI/install.sh . --platform apple     # apple | android | both
```

The installer copies skills, platform-matching rules, settings, a starter `CLAUDE.md` (from `templates/CLAUDE.template.md`), and appends `.gitignore` entries. It never overwrites existing `CLAUDE.md` or `settings.json` — it prints what it skipped.

Then customize the new repo's `CLAUDE.md` to describe **that** project's specifics: modules, build commands, dependency graph, gotchas. Keep the steering rules and skills as-is — they apply to any modern Apple or Android app.

## Invoking the skills

Skills auto-trigger when the description matches the task. You can also invoke them explicitly:

- "Use `swift-concurrency-pro` to review the changes in `NetworkClient.swift`."
- "Use `swiftui-pro` to review `SettingsView.swift` for modern API and a11y."
- "Use `swift-testing-pro` to write tests for `UserSession`."

Each skill produces a file-by-file findings report with before/after code fixes and a prioritized summary.

## Baseline conventions (steering rules)

The rules in `.claude/rules/` are loaded automatically for every Swift file in the target repo. They encode:

### Swift 6.2 strict concurrency (`apple-swift6-strict-concurrency.md`)

- Strict concurrency is a compile error, not a warning.
- Prefer `@MainActor` at the **type** level over per-method annotations.
- Never use `@unchecked Sendable` — redesign instead.
- Avoid `DispatchQueue.main.async`; prefer structured concurrency.
- Avoid global mutable `static var` state.
- ObjC delegate conformances use `@preconcurrency`, not `nonisolated` methods.

### Android project rules (`android-project-rules.md`)

Scoped to `**/*.{kt,kts}`. Encodes:

- **Stack:** Kotlin + Jetpack Compose (no XML), MVVM, Hilt DI, StateFlow + `collectAsStateWithLifecycle()`, Retrofit + Moshi.
- **Style:** ktlint, `PascalCase` Composables, `camelCase` members, no wildcard imports.
- **Workflow:** `./gradlew assembleDebug | test | ktlintCheck` (run ktlint before every commit).
- **Safety:** never hardcode secrets; all UI text in `strings.xml`.

### Apple accessibility (`apple-accessibility-best-practices.md`)

- Every interactive element needs `.accessibilityLabel` (and `.accessibilityHint` where non-obvious).
- Decorative icons use `.accessibilityHidden(true)`.
- Section headers use `.accessibilityAddTraits(.isHeader)`.
- Context menus must mirror their actions in `.accessibilityActions` (context menus are not in VoiceOver's default rotor).
- Always check `@Environment(\.accessibilityReduceMotion)` before animating.
- Use semantic fonts (`.font(.headline)`), never `.font(.system(size:))`.
- Never hardcode English in accessibility strings — localize everything.

### Android accessibility (`android-accessibility-best-practices.md`)

Scoped to `**/*.{kt,kts}`. Encodes:

- Every meaningful `Image`/`Icon` sets `contentDescription` via `stringResource()`; decorative ones pass `null`.
- Compose semantics: `Modifier.semantics(mergeDescendants = true)` for compound rows, `heading()` for section titles, explicit `Role.Button/Checkbox/Switch` for custom controls, `stateDescription` for changing values.
- Touch targets ≥ 48dp via `Modifier.minimumInteractiveComponentSize()`.
- Text sizes in `sp` (not `dp`); never truncate critical content without fallback in semantics.
- Custom actions mirror gesture affordances via `CustomAccessibilityAction`.
- Respect `LocalAccessibilityManager.current?.isReduceMotionEnabled` in animations.
- WCAG AA contrast (4.5:1 body / 3:1 large text); never convey state by color alone.
- All user-facing strings via `stringResource(R.string.…)` — including a11y attributes.

## Guidance for adopting teams

When you copy this into a new app, also think about adding:

1. **Project-specific `CLAUDE.md`** at the repo root. Describe the module graph, build commands per platform, localization module, and any non-obvious gotchas. Claude reads it first.
2. **A `.swiftlint.yml`** with your line-length, identifier, and file-length rules. Run it as an Xcode Build Phase and in CI.
3. **A `settings.local.json`** (git-ignored) for per-developer permission overrides — never check it in.
4. **Domain-specific rules** in `.claude/rules/` as you discover patterns. Each rule file should have frontmatter with `description:` and `globs:` so Claude applies it only where relevant.
5. **Project-specific skills** in `.claude/skills/` for review workflows unique to your app (e.g., `core-data-migration-pro`, `localization-pro`).

## Writing your own rules

Each rule file in `.claude/rules/` should be a short, enforceable list of dos and don'ts:

```markdown
---
description: One-line summary of what this rule enforces
globs: "**/*.swift"
---

# Rule Name

Short intro: why this rule exists.

## Core Rules
- Bullet points with concrete, enforceable guidance.

## Patterns to Follow
- Code snippets showing the correct form.
```

Keep rules **prescriptive, not descriptive**. "Use `@MainActor` at the type level" is actionable; "Think about isolation" is not.

## Writing your own skills

Skills live in `.claude/skills/<skill-name>/` and must contain a `SKILL.md` with YAML frontmatter:

```markdown
---
name: your-skill-name
description: When to invoke this skill. First-person summary of what it does.
license: MIT
---

<Procedural instructions for Claude>
```

Split deep context into `references/<topic>.md` files the skill loads on demand — keeps the main skill compact and avoids blowing context on tangential material. See `swift-concurrency-pro` for a mature example.

## References: source repos this was distilled from

- **KozBon** — production multi-platform Bonjour service discovery app. Source of the strict-concurrency and accessibility rules.
- **BasicSwiftUtilities** — foundational Swift 6 utilities package (logging, retry, storage, SwiftUI/UIKit helpers). Source of the skill bundles.

The skills were originally authored by Paul Hudson (MIT licensed); the rules and onboarding structure are adapted from production usage across the Kozinga app projects.

## License

MIT. See `LICENSE`. The bundled skills under `.claude/skills/` retain their original MIT license and author attribution in their frontmatter.
