# CLAUDE.md

<!--
  This file is the single most important onboarding doc for Claude Code. It is
  loaded at the start of every session in this repo. Keep it current, concrete,
  and short — Claude reads it, not your README.

  Replace every <PLACEHOLDER> below, and delete sections that don't apply.
  Delete this comment block when you're done.
-->

## Project Overview

<PROJECT_NAME> is <ONE_SENTENCE_DESCRIPTION>. <BUNDLE_ID>.

- Platforms: <iOS | macOS | tvOS | watchOS | visionOS — list what you ship>
- Minimum OS: <iOS 18 / macOS 15 / ...>
- Language: Swift 6.2 with strict concurrency
- Mixed-language: <yes — Objective-C in Legacy/ | no>

## Build & Run

```bash
# Build for iOS Simulator — replace scheme/destination to match this repo
xcodebuild -workspace <Workspace>.xcworkspace -scheme <Scheme> \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' build

# Build for macOS
xcodebuild -workspace <Workspace>.xcworkspace -scheme <Scheme> \
    -destination 'platform=macOS' build

# Run app tests via Xcode
xcodebuild test -workspace <Workspace>.xcworkspace -scheme <Scheme> \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'

# Run SPM package tests (faster, no simulator) — if you have local packages
swift test --package-path <PackagePath>
```

## Architecture

- Framework: SwiftUI <+ MVVM | + The Composable Architecture | + ...>
- Navigation: <NavigationStack / NavigationSplitView>
- DI: <SwiftUI Environment / dependency container>
- Persistence: <Core Data / SwiftData / GRDB / none>
- Networking: <URLSession / Alamofire / ...>
- Localization: <String Catalog / NSLocalizedString — module name>

## Module Graph

<!-- If your project has more than one module/package, list them with a one-line purpose. Delete if monolithic. -->

| Module | Purpose | Key Types |
|--------|---------|-----------|
| <ModuleName> | <purpose> | <important types> |

## Code Conventions

- Use `// MARK: -` section headers to organize code within files.
- One type per file, feature-based folder organization.
- Use the zero-parameter `onChange(of:)` closure (iOS 17+), not the deprecated `{ _ in }` form.
- All user-facing strings must use <YourLocalizationModule>.Strings.* — never hardcode English in views.
- <Other project-specific conventions>

## Swift 6.2 Strict Concurrency

(Enforced via `.claude/rules/apple-swift6-strict-concurrency.md`. Project specifics:)

- View models: `@MainActor @Observable final class`
- Service classes: `@MainActor final class` (implicitly `Sendable`)
- <Project-specific isolation patterns>

## SwiftUI MVVM

(Enforced via `.claude/rules/apple-swiftui-mvvm.md`. Project specifics:)

- View models live in <which module/folder>.
- Long-lived dependencies <captured at init via DI container | from Environment>.
- <Anything specific about how this repo names/organizes view models>

## AI / Foundation Models

<!-- Delete if the app doesn't integrate Apple Foundation Models. -->

- Entry point: <session holder type, e.g., `ChatSession`>
- Protocol wrapper: <protocol name>
- Availability utility: <type that surfaces `SystemLanguageModel.default.availability`>
- Injection: `@Environment(\.<key>)` with lazy local fallback
- Mock / Simulator strategy: <how tests/the simulator demo work>
- Minimum OS: iOS 26 / macOS 26 (the `@available` boundary for `FoundationModels`)

## Objective-C / Mixed-Language

<!-- Delete if pure-Swift. -->

- Bridging header: `<ProjectName>-Bridging-Header.h`
- Legacy ObjC lives in: <path>
- Swift wrappers around ObjC APIs live in: <path>
- Migration policy: <e.g., "rewrite to Swift on touch" or "stable, leave it">

## Testing

- Framework: Swift Testing (`@Test`, `@Suite`, `#expect`)
- Run: `swift test --package-path <PackagePath>` and/or `xcodebuild test ...`
- `@MainActor` tests for `@MainActor`-isolated types (Core Data, view models).
- <Test-isolation caveats>

## SwiftLint

- Config: `.swiftlint.yml`
- Integration: <Xcode Build Phase / GitHub Actions>
- Run manually: `swiftlint lint`
- Excluded: <paths>

## CI / GitHub Actions

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| <file.yml> | <event> | <summary> |

## Important Gotchas

<!-- The things that took you a day to figure out and don't want to re-explain. -->

- <e.g., Core Data model is in a package; SPM CLI can't compile .xcdatamodeld — use xcodebuild>
- <e.g., NSBonjourServices in Info.plist must mirror the service-type library>
- <e.g., A specific feature flag that gates AI features>

## Git workflow expectations

(Inherited from AppBootstrapAI — keep these unless your team has a stronger reason to override.)

- **Never commit without an explicit instruction.** Working-tree edits are fine; promoting them to a commit requires a direct ask (*"commit this"*, *"make a commit"*). If unsure, ask first.
- **Never push to `origin` without an explicit instruction.** Pushing has visible side effects (CI, teammates, published branches). Always wait for *"push"* / *"push to origin"* / *"open a PR"*.
- **Never amend** an existing commit unless the user explicitly asks. Default to a new commit.
- **Never run destructive git commands without confirmation:** `git push --force`, `git reset --hard`, `git checkout .`, `git clean -f`, `git branch -D`, interactive `git rebase`. Name the command and ask before running.
- **Never skip git hooks** (`--no-verify`, `--no-gpg-sign`) unless explicitly requested.
- **Never force-push to `main`/`master`** even when asked — warn and offer a safer path.
- **When commits ARE requested**, follow project commit-message conventions, stage specific files (not `git add -A` which captures `.env`/credentials), prefer new commits over `--amend`.

The principle: commits and pushes are user-driven. Edits are AI-driven.

## AI Rules and Skills

This repo uses the AppBootstrapAI bundle in `.claude/`:

- **Rules** (`.claude/rules/`) auto-apply to matching files. See each rule's `globs:` for scope.
- **Skills** (`.claude/skills/`) fire on demand — e.g., *"Use `swift-concurrency-pro` to review `NetworkClient.swift`."*
- Local permission overrides go in `.claude/settings.local.json` (git-ignored).

When you discover a new pattern that should be enforced project-wide, add it to `.claude/rules/<name>.md` with `description:` and `globs:` frontmatter. Keep rules short and prescriptive.
