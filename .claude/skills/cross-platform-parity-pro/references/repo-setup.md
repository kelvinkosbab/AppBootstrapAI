# Setting up a two-platform repo for AI-assisted work

## Layout

```
MyApp/
├── CLAUDE.md
├── .claude/                  # this bundle, installed with --platform both
│   └── agents/               # per-platform subagents (below)
├── apple/
│   ├── CLAUDE.md
│   ├── MyApp.xcodeproj
│   └── MyAppPackages/        # scripts/scaffold-spm-package.sh output
├── android/
│   ├── CLAUDE.md
│   ├── settings.gradle.kts
│   └── app/, core/, feature/
├── shared/
│   ├── api/openapi.yaml
│   ├── design-tokens/
│   ├── analytics/events.yaml
│   └── strings/              # only if the translation platform isn't the source
└── docs/
    ├── adr/
    ├── features/
    └── parity.md
```

Bring two existing repos together with `git subtree add` (or `git filter-repo` + merge) so each platform keeps its history. Move one platform at a time, keeping CI green.

## Install the bundle

```bash
/path/to/AppBootstrapAI/install.sh . --platform both
# plus opt-ins the project uses, e.g.
/path/to/AppBootstrapAI/install.sh . --platform both --features recommended,architecture,deployment
```

Apple rules fire on Swift files and Android rules on Kotlin files, so one root install serves both directories.

## Root CLAUDE.md (shared facts only)

```markdown
# CLAUDE.md

MyApp ships on iOS/iPadOS/macOS (`apple/`) and Android (`android/`) from one repo.
Each platform has its own CLAUDE.md with build commands; read it before working there.

## How we build features
1. Spec in `docs/features/<feature>.md` (states, strings, icons, events, links, a11y, acceptance).
2. Implement on one platform, port to the other with `cross-platform-parity-pro`, or both in parallel worktrees.
3. Same names on both sides (types, modules, string keys with `.`→`_` on Android, icon vocabulary, events, flags).
4. Update `docs/parity.md` in the same PR.

## Shared contracts (never hand-edit generated output)
- API: `shared/api/openapi.yaml` → `apple/…/Generated`, `android/core/network/build/generated`
- Tokens: `shared/design-tokens` → `npm run tokens` → both design-system modules
- Analytics: `shared/analytics/events.yaml` → `scripts/gen-events`

## Verify
- Apple: see `apple/CLAUDE.md` ("Verify")
- Android: see `android/CLAUDE.md` ("Verify")
- A change under `shared/` must pass both.

## Decisions
- Native UI on both; no shared code (ADR 0001). <!-- or: KMP for domain + data (ADR 0001) -->
```

## Platform CLAUDE.md files

`apple/CLAUDE.md` and `android/CLAUDE.md` follow the bundle's `templates/CLAUDE.template.apple.md` / `templates/CLAUDE.template.android.md`: build/test/lint commands under a "Verify" heading, module graph, and gotchas. Claude Code loads them when it works in those directories, so the root file stays short.

## Per-platform subagents

Subagents keep each platform's work in its own context window, so a cross-platform task doesn't fill one session with both toolchains' output. Define them in `.claude/agents/`:

```markdown
---
name: apple-engineer
description: Implements and verifies changes in apple/ (Swift 6, SwiftUI, SPM). Use for any task scoped to the Apple app, including the Apple half of a cross-platform feature.
---

You work only inside `apple/` (and read `shared/` and `docs/`). Read `apple/CLAUDE.md` first.
Follow the apple-* rules. Use the names in the feature spec exactly.
Before finishing, run the Verify commands in `apple/CLAUDE.md` and report the results.
If the task needs a change in `shared/` or `android/`, stop and say so instead of making it.
```

```markdown
---
name: android-engineer
description: Implements and verifies changes in android/ (Kotlin, Compose, Hilt, Gradle). Use for any task scoped to the Android app, including the Android half of a cross-platform feature.
---

You work only inside `android/` (and read `shared/` and `docs/`). Read `android/CLAUDE.md` first.
Follow the android-* rules. Use the names in the feature spec exactly.
Before finishing, run the Verify commands in `android/CLAUDE.md` and report the results.
If the task needs a change in `shared/` or `apple/`, stop and say so instead of making it.
```

A typical prompt: *"Implement `docs/features/task-list.md`: use apple-engineer and android-engineer in parallel, then compare both against the spec's state table."* Subagent file format and available fields (tools, model) are in the Claude Code docs; restrict `tools` if you want them read-only for audits.

## Shared contracts

### API

- Apple: [swift-openapi-generator](https://github.com/apple/swift-openapi-generator) as an SPM build plugin in the networking module (the spec file and an `openapi-generator-config.yaml` live in the target's sources; symlink or copy from `shared/api/` in a pre-build step).
- Android: the OpenAPI Generator Gradle plugin (`org.openapi.generator`) in `:core:network`, `inputSpec` pointing at `shared/api/openapi.yaml`, output in `build/generated`.
- Generated models are DTOs — map them to domain models in each platform's repository (repository-pattern rules).

### Design tokens

- Source: `shared/design-tokens/*.json` (color roles with light/dark values, spacing, radii, type roles).
- Generate with [Style Dictionary](https://styledictionary.com) or a small script. Style Dictionary ships iOS Swift and Jetpack Compose output formats; check its docs for the current format names for your version.
- Apple's design-system rule wants colors that adapt to appearance and contrast: generate asset-catalog color sets (Any/Dark/High Contrast) or a Swift file that builds dynamic colors, rather than a flat list of static colors.
- Android: generate the brand palette and extended colors; Material Theme Builder still produces the full `ColorScheme` from the seed.
- Commit the generated files or generate in the build, but pick one and say which in the root CLAUDE.md.

### Strings

- Prefer the translation platform as the source and export both formats from it.
- Keys: one name, `.`-separated in the catalog, `_`-separated in `strings.xml`. Format arguments differ (`\(name)` vs `%1$s`); the export maps them, or a script does.

### Analytics and flags

- `events.yaml` lists each event's name, properties, and types; a script generates a Swift enum and a Kotlin sealed class. Call sites use the generated API.
- Flag keys and defaults live in one list; each platform exposes typed accessors.

## PR template

```markdown
## Platforms
- [ ] Apple
- [ ] Android
- Other platform: done in this PR / follow-up #___ / not applicable because ___
- [ ] `docs/parity.md` updated
```

## CI path filters

```yaml
# .github/workflows/apple.yml
on:
  pull_request:
    paths: ['apple/**', 'shared/**', '.github/workflows/apple.yml']
jobs:
  build-test:
    runs-on: macos-26          # pin an Apple-silicon image with the Xcode you need
```

```yaml
# .github/workflows/android.yml
on:
  pull_request:
    paths: ['android/**', 'shared/**', '.github/workflows/android.yml']
jobs:
  build-test:
    runs-on: ubuntu-latest
```

```yaml
# .github/workflows/parity.yml — string-key and icon diffs (parity-audit.md)
on:
  pull_request:
    paths: ['apple/**/*.xcstrings', 'android/**/res/values/*.xml', 'apple/**/AppIcon*.swift', 'android/**/AppIcons*.kt', 'shared/**']
```

Required status checks: make both platform workflows required. With path filters, a workflow that doesn't run leaves its required check pending; use a small "always runs" job that passes when its paths didn't change, or your CI's equivalent of conditional required checks.
