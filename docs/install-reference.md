# Install reference

Every `install.sh` command and flag. `./install.sh --help` prints the same
reference. Examples use the bare/`install` form; prefix any
of them with a verb (`install` / `upgrade` / `uninstall` / `list` / `setup`) or
use the equivalent `--flag` — they're interchangeable. From the root of a new app
repo:

```bash
# Zero-flag install — installer auto-detects platform from the target dir.
# Package.swift / *.xcodeproj → apple; build.gradle* / gradlew → android;
# both present → both; neither (fresh repo) → falls back to both.
# The header prints which signals matched so you can verify.
/path/to/AppBootstrapAI/install.sh .

# Explicit platform always wins over detection
/path/to/AppBootstrapAI/install.sh . --platform apple
/path/to/AppBootstrapAI/install.sh . --platform android
/path/to/AppBootstrapAI/install.sh . --platform both

# Opt in to the FULL bundle including specialized opt-ins
# (persistence/Core Data, ai/Foundation Models, migration, shrinking)
/path/to/AppBootstrapAI/install.sh . --platform both --features all

# Pick specific feature categories
/path/to/AppBootstrapAI/install.sh . --platform apple --features core,testing,docs

# Apple legacy project — Objective-C only
/path/to/AppBootstrapAI/install.sh . --platform apple --apple-language objc

# Apple mixed-language — Swift + ObjC
/path/to/AppBootstrapAI/install.sh . --platform apple --apple-language both

# Preview what any flag combo will install (no files written, with category tags)
/path/to/AppBootstrapAI/install.sh --list --platform android --features all

# Same catalog as JSON (for automation / the MCP server)
/path/to/AppBootstrapAI/install.sh --list --json --platform apple --features all

# Show what an install would do without actually writing files
/path/to/AppBootstrapAI/install.sh /target --platform apple --features all --dry-run

# Compose recommended + specific opt-ins (instead of writing the CSV by hand)
/path/to/AppBootstrapAI/install.sh . --platform apple --features recommended,ai,persistence

# visionOS app — pull in the visionOS rule (scene types, immersion styles,
# RealityKit conventions, head-mounted-display accessibility, USDZ pipeline).
# Either name the platform, or add the spatial feature — they're equivalent:
/path/to/AppBootstrapAI/install.sh . --platform apple --apple-platforms ios,visionos
/path/to/AppBootstrapAI/install.sh . --platform apple --features recommended,spatial

# Target specific Apple platforms (default is everything except visionOS)
/path/to/AppBootstrapAI/install.sh . --platform apple --apple-platforms ios,macos

# Shipping to testers — add the deployment category for TestFlight (Apple) +
# Play beta (Android): versioning, signing, CI patterns, common gotchas
/path/to/AppBootstrapAI/install.sh . --features recommended,deployment

# Bootstrap + wire in MCP servers at the same time
# (writes one mcpServers entry per recipe into .claude/settings.local.json)
/path/to/AppBootstrapAI/install.sh . --platform apple --with-mcps xcodebuildmcp,sentry

# Browse available MCP recipes (see what --with-mcps can install)
/path/to/AppBootstrapAI/install.sh --list-mcps

# Install for a non-Claude agent — writes that agent's native file shape
/path/to/AppBootstrapAI/install.sh . --agents copilot   # → .github/instructions/*.instructions.md
/path/to/AppBootstrapAI/install.sh . --agents cursor    # → .cursor/rules/*.mdc
/path/to/AppBootstrapAI/install.sh . --agents gemini    # → GEMINI.md
/path/to/AppBootstrapAI/install.sh . --agents codex     # → AGENTS.md
/path/to/AppBootstrapAI/install.sh . --agents kiro      # → .kiro/steering/*.md

# Mixed team — install for several agents in one run
/path/to/AppBootstrapAI/install.sh . --agents claude,copilot,cursor

# Everything (claude + copilot + cursor + gemini + codex)
/path/to/AppBootstrapAI/install.sh . --agents all

# Existing install? Diff and apply updates without losing local edits
/path/to/AppBootstrapAI/install.sh . --upgrade           # plan-only preview
/path/to/AppBootstrapAI/install.sh . --upgrade --apply   # execute the plan

# Full help — documents --features categories, --with-mcps recipes, --agents tokens
/path/to/AppBootstrapAI/install.sh --help
```

Every real install writes a manifest at `.claude/.appbootstrap-manifest.json` listing every file that was installed plus the flags used. The manifest is what powers `--upgrade`'s 3-way diff against future bundle versions.

**The default `--features recommended` set** covers what most apps need on day one: `core` (project docs) + `concurrency` + `ui` + `testing` + `docs` (code documentation) + `error-handling` + `packaging` + `logging` + `localization` + `linting` (SwiftLint+formatter / ktlint+detekt+Android Lint) + `compliance` (region-specific App Store / Play rules) + `memory-storage` (leaks, footprint, file locations, backup, app size) + `performance` (Instruments / `xctrace` profiling and hang triage). Specialized opt-ins not in `recommended`: `persistence` (Core Data / SwiftData), `ai` (Apple Foundation Models + Android Gemini Nano / Firebase AI Logic), `migration` (XML → Compose), `shrinking` (R8/ProGuard), `spatial` (visionOS scene types, immersion styles, spatial gestures, RealityKit conventions), `deployment` (TestFlight + Play beta tracks — versioning, signing, CI patterns, common gotchas), `architecture` (Android MVVM / unidirectional data flow + the repository pattern for both platforms), `intents` (App Intents, App Shortcuts, Siri tools), `security` (Xcode security settings, Enhanced Security, C bounds safety).

**The default `--agents claude` set** writes the native Claude Code layout. Pass `--agents copilot|cursor|gemini|codex|kiro|android-studio|all` (additive CSV) and the installer also drops the matching file shape for those agents (per-rule files for Copilot `.instructions.md`, Cursor `.mdc`, and Kiro `.kiro/steering/*.md`; a short rule index for Gemini and Codex). See [Using with non-Claude AI agents](agents.md) for the per-agent table.

The installer:

- Copies skills matching the platform/language/features intersection (Apple skills when `--agents claude` and Apple/Swift in scope; Android skills similarly). Skills go to Claude and, with `--agents android-studio`, to `.agents/skills/`; other agents get rules only.
- Copies platform-matching `.claude/rules/` filtered by `--features` (when `--agents claude` is selected).
- Generates per-agent files for each agent in `--agents` (e.g., `.github/instructions/*.instructions.md`, `.cursor/rules/*.mdc`, `GEMINI.md`, `AGENTS.md`).
- Copies `.claude/settings.json` (only if `--agents claude` and one doesn't already exist).
- Renders the **platform-appropriate** `CLAUDE.template.*.md` into `CLAUDE.md` (only if `--agents claude` and missing): `apple` → `CLAUDE.template.apple.md`, `android` → `CLAUDE.template.android.md`, `both` → `CLAUDE.template.md`.
- Appends platform-specific entries to `.gitignore`, deduped by marker. Adds `.cursor/state*` / `.cursor/.cache/` entries when `--agents cursor` is selected.
- Writes `.claude/.appbootstrap-manifest.json` recording every installed file (with per-file SHA-256) plus the full selection (`--platform`, `--apple-language`, `--features`, `--agents`).

It never overwrites an existing `CLAUDE.md`, `settings.json`, or any agent file (`copilot-instructions.md`, `GEMINI.md`, etc.) — it prints what it skipped so you can merge.

`--dry-run` skips every write but still prints what would happen, so you can preview before committing to an upgrade.

After install, edit the new `CLAUDE.md` (or your agent's equivalent) and fill in the `<PLACEHOLDER>` sections. Keep the bundled rules and skills as-is unless you need to extend them.

> **Using a different agent?** `install.sh --agents copilot|cursor|gemini|codex|kiro|android-studio|all` writes the right files natively. See [Using with non-Claude AI agents](agents.md) for the per-agent file layout. For agents not in that built-in set, point a sync tool like [`ruler`](https://github.com/intellectronica/ruler) at `.claude/`.

## Flags, templates, and bundle files

- **`settings.json`** — safe defaults: builds and tests (`xcodebuild`, `swift build`/`test`, `swiftlint`, `./gradlew`, `ktlint`), read-only `git` and `gh` verbs, and Apple/Android docs domains for `WebFetch`. Commits, pushes, and `gh` writes still prompt. A `deny` list blocks force-pushes, `gh repo delete`, and reading `.env`, signing keys, and keystores.
- **`.gitignore`** — recommended entries for Xcode, SPM, CocoaPods, Carthage, fastlane, plus Gradle/Android Studio/Kotlin.
- **`install.sh`** — one-command bootstrap into any target repo.
  - **Commands** (verb form): `install [TARGET]` (default — verb optional), `recommend [TARGET]` (analyze a dir → suggested command, `--json` for agents), `upgrade TARGET`, `uninstall TARGET`, `list`, `list-mcps`, `setup` (guided), `help`. Each has a legacy `--flag` alias (`--upgrade`, `--uninstall`, `--list`, `--list-mcps`, `-i`/`--interactive`, `-h`/`--help`) — verbs and flags are interchangeable, so existing scripts keep working. A directory whose name collides with a verb can be targeted via an explicit path (`./upgrade`) or the `--flag` form.
  Flags:
  - `-i` / `--interactive` — guided, prompt-driven setup. Detects create vs. adopt vs. update and walks through platform / Apple-language / features / agents / MCP recipes with defaults. Works at a TTY or from piped stdin (Enter accepts each default); prints a plan and confirms before writing. See [Getting started](../README.md#getting-started).
  - `--new` — create the target directory (and parents) and `git init` a fresh repo before installing, for green-field projects. Light scaffolding only — does not generate an Xcode/Gradle project. Install-only (rejected with `--upgrade`/`--uninstall`).
  - `--force` — allow a plain `install` over a directory that's already a managed AppBootstrapAI install. Without it, re-installing over a managed repo is refused with guidance to use `--upgrade` (which preserves the manifest baseline). Install-only.
  - `--platform apple|android|both` — optional; if omitted, the installer auto-detects from the target dir (`Package.swift` / `*.xcodeproj` → apple; `build.gradle*` / `gradlew` → android; both present → both; neither → falls back to `both`). Detection result + matched signals print in the install header. Explicit `--platform` always wins.
  - `--apple-language swift|objc|both` (legacy ObjC projects skip Swift-only rules)
  - `--apple-platforms ios,macos,tvos,watchos,visionos|all` — which Apple sub-platforms you target. Default `ios,macos,tvos,watchos` (every platform **except** visionOS — the lean default for typical app projects). Only meaningful when Apple is in scope. `visionos` stays in sync with the `spatial` feature: naming it installs the visionOS rule, omitting it keeps it out. **`macos` gates the touch-on-Mac rule** (`apple-mac-touch.md`) — drop it for an iOS-only app. Other tokens are recorded in the manifest for future platform-specific rules.
  - `--android-platforms phone,tablet,wear,tv,auto|all` — which Android form factors you target. Default `phone,tablet`. Only meaningful when Android is in scope. **`tablet` gates the large-screen / foldable rule** (`android-large-screen-best-practices.md`) **and the `android-adaptive-layout-pro` skill** — drop it for a phone-only app. Other tokens are recorded in the manifest for future form-factor rules (Wear OS / Android TV / Auto would gate the same way).
  - `--features all|recommended|<csv>` — **default `recommended`** is a curated subset for most apps (now includes `linting`, `compliance`, `memory-storage`, and `performance`); `all` adds specialized opt-ins (`persistence`, `ai`, `migration`, `shrinking`, `spatial`, `deployment`, `architecture`, `intents`, `security`); custom CSVs like `core,testing,docs` give fine-grained control
  - `--list` previews the catalog with one-line descriptions + category tags
  - `--list --json` emits the same catalog as machine-readable JSON (used by the MCP server)
  - `--list-mcps` lists available MCP-server recipes (name, platform, description, homepage)
  - `--with-mcps <csv>` writes one `mcpServers.<name>` entry per recipe into `.claude/settings.local.json`. Existing entries are never overwritten. Setup notes (auth, env vars) print after install. See [`mcp-recipes/`](../mcp-recipes/) for the available recipes.
  - `--agents <csv>` picks which AI agents to install for. Default `claude`; additive options: `copilot` (writes `.github/instructions/*.instructions.md`), `cursor` (writes `.cursor/rules/*.mdc`), `gemini` (writes a `GEMINI.md` index), `codex` (writes an `AGENTS.md` index), `kiro` (writes `.kiro/steering/*.md`), `android-studio` (writes the `AGENTS.md` index, Android skills in `.agents/skills/`, and `.aiexclude`), or `all`. Same rule content, per-agent file shape. Skills go to Claude and Android Studio only.
  - `--dry-run` shows what an install would do without writing any files
  - `--upgrade` prints a per-file plan of what would change if you re-installed today — classified as up-to-date / safe update / local-edits / conflict / orphan / addition / out-of-scope / rename. Add `--apply` to execute the plan; `--force-conflicts` to overwrite locally-edited files where the bundle also changed; `--prune` to delete orphans + out-of-scope files; `--migrate-manifest` to bring a v1 manifest forward. The header prints a GitHub compare URL when commits differ. See [Upgrading an existing install](upgrading.md).
  - `--uninstall` reverses install: deletes every tracked file whose current hash matches what was installed (locally-edited files kept unless `--force-conflicts`; `CLAUDE.md` / `settings.json` kept unless `--purge`). MCP entries are removed if unchanged, unless `--keep-mcps`. Strips the `.gitignore` block and the manifest itself. See [Removing the install](upgrading.md#removing-the-install).
  - `--help` documents every flag and enumerates all 22 categories
  - Every install writes a manifest at `.claude/.appbootstrap-manifest.json` (schema v2 — records per-file SHA-256 hashes so `--upgrade` can diff 3-way: installed vs. current disk vs. bundle)
- **Three starter `CLAUDE.md` templates** — `templates/CLAUDE.template.apple.md`, `templates/CLAUDE.template.android.md`, `templates/CLAUDE.template.md` (cross-platform). The installer picks the right one based on `--platform`.
- **`templates/Package.template.swift`** — starter Swift Package Manager manifest with a `makeTargets(name:dependencies:hasTests:hasResources:testDependencies:testResources:)` helper. Adding a new module is a two-line change: one line in `products:` and one `+ makeTargets(...)` block in `targets:`. Copy it into a new SPM package as `Package.swift` and fill in the placeholders.
- **`scripts/scaffold-spm-package.sh`** — generates a KozBon-style local package (`<App>Packages/`) so an existing app can move its logic out of the `.xcodeproj` and into modules. Emits a `makeTargets()`-based `Package.swift` from `--modules Core,…,AppCore` plus a compiling source + passing test placeholder per module; a module named `AppCore` becomes the umbrella and the only product, with an `AppRootView` for the app's `@main`. `--main-actor all` writes a tools-6.2 manifest where UI and feature modules default to `@MainActor` (`.defaultIsolation`) and Core stays nonisolated. CI builds and tests both forms. Non-destructive (never overwrites; `--dry-run` / `--force`). Pairs with the `apple-modular-architecture.md` rule.
