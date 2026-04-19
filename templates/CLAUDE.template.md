# CLAUDE.md

<!--
  This file is the single most important onboarding doc for Claude Code. It is
  loaded at the start of every session in this repo. Keep it current, concrete,
  and short — Claude reads it, not your README.

  Replace every <PLACEHOLDER> below, and delete sections that don't apply.
  Delete this comment block when you're done.
-->

## Project Overview

<PROJECT_NAME> is <ONE_SENTENCE_DESCRIPTION>. <BUNDLE_ID_OR_PACKAGE>.

- Primary platform(s): <apple | android | both>
- Minimum OS: <iOS 18 / Android 14 / ...>
- Language: <Swift 6.2 / Kotlin 2.x>

## Build & Run

```bash
# Apple — replace scheme/destination to match this repo
xcodebuild -workspace <Workspace>.xcworkspace -scheme <Scheme> \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' build
swift test --package-path <PackagePath>   # if SPM-based

# Android
./gradlew assembleDebug
./gradlew test
./gradlew ktlintCheck
```

## Architecture

<!-- A 3-5 bullet summary Claude can orient on. What framework, what pattern, what DI, what persistence. -->

- Framework: <SwiftUI / Jetpack Compose>
- Pattern: <MVVM / TCA / ...>
- DI: <SwiftUI Environment / Hilt / manual>
- Persistence: <Core Data / SwiftData / Room / ...>
- Networking: <URLSession / Retrofit+Moshi / ...>

## Module Graph

<!-- If your project has more than one module/package, list them here with a one-line purpose. -->

| Module | Purpose | Key Types |
|--------|---------|-----------|
| <ModuleName> | <purpose> | <important types> |

## Code Conventions

<!-- Project-specific style beyond what the rules in .claude/rules/ already enforce. -->

- <e.g., One type per file, feature-based folders, `// MARK: -` section headers>
- <e.g., Localization module name and access pattern>
- <e.g., SwiftLint / ktlint config location>

## Testing

- Framework: <Swift Testing / JUnit + Roborazzi>
- Run: <command to run all tests>
- <Any test-isolation caveats — @MainActor, Robolectric, in-memory DB, etc.>

## CI

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| <file.yml> | <event> | <summary> |

## Important Gotchas

<!-- The things that took you a day to figure out and don't want to re-explain. Claude will thank you. -->

- <e.g., Core Data model is in a package; SPM CLI can't compile .xcdatamodeld — use xcodebuild>
- <e.g., NSBonjourServices must mirror the service-type library>
- <e.g., Hilt does not inject into Composables directly — use hiltViewModel()>

## AI Rules and Skills

This repo uses the AppBootstrapAI bundle in `.claude/`:

- **Rules** (`.claude/rules/`) are auto-applied to matching files. See each file's frontmatter `globs:` for scope.
- **Skills** (`.claude/skills/`) are invoked on demand — e.g., *"Use `swift-concurrency-pro` to review `NetworkClient.swift`."*
- Local permission overrides go in `.claude/settings.local.json` (git-ignored).

When you discover a new pattern that should be enforced project-wide, add it to `.claude/rules/<name>.md` with `description:` and `globs:` frontmatter. Keep rules short and prescriptive.
