# AppBootstrapAI

A drop-in bundle of **Claude Code skills** and **AI steering rules** for bootstrapping new app projects. Covers Apple platforms (iOS, macOS, tvOS, watchOS, visionOS) and Android in one bundle, so single-platform and mixed-stack teams can share one source of truth.

This repo is not a Swift package — it's a curated `.claude/` directory plus onboarding docs. Copy it into any new app and Claude Code picks up consistent review, testing, and style guidance on day one.

**Claude Code is the native target — but the rule content is plain markdown.** Teams on Cursor, Gemini CLI, Kiro, Codex CLI, GitHub Copilot, Cline, Goose, Roo, Windsurf, etc. can fan the same rules out to their agent of choice via [`ruler`](https://github.com/intellectronica/ruler), [`block/ai-rules`](https://github.com/block/ai-rules), or [`ai-rules-sync`](https://github.com/lbb00/ai-rules-sync). See [Using with non-Claude AI agents](#using-with-non-claude-ai-agents) below.

## What you get

### Apple

- **`apple-swift6-strict-concurrency.md`** — Swift 6.2 strict concurrency, enforced on every `.swift` file.
- **`apple-accessibility-best-practices.md`** — VoiceOver, Dynamic Type, Reduce Motion for SwiftUI (including streaming AI text).
- **`apple-foundation-models.md`** — Apple Foundation Models patterns: session ownership, two-level availability gating, streaming placeholder-then-mutate, `Task.isCancelled` discipline, protocol + mock + simulator testability.
- **`apple-swiftui-mvvm.md`** — SwiftUI MVVM conventions: when to extract a view model, `@State` vs `@Bindable` ownership, dependency plumbing, what stays on the View vs the view model, splitting large VMs across extension files.
- **`apple-objc-best-practices.md`** — Modern Objective-C for legacy / mixed-language codebases: ARC discipline, nullability, lightweight generics, `instancetype`, designated initializers, modern literals/blocks, Swift bridging-header conventions.
- **`apple-objc-accessibility-best-practices.md`** — UIKit accessibility in Objective-C: `accessibilityLabel` / `accessibilityHint` / `accessibilityTraits` discipline, `accessibilityIdentifier` vs `accessibilityLabel`, Dynamic Type via `preferredFontForTextStyle:`, `UIAccessibilityIsReduceMotionEnabled()`, VoiceOver announcements (`UIAccessibilityPostNotification`), modal-focus management (`accessibilityViewIsModal`), custom-action support.
- **`apple-testing-strategy.md`** — what to test (and what not), Given/When/Then naming, determinism (inject clocks/UUIDs/network), Swift Testing vs XCTest split, XCUITest discipline, CI coverage gates with sensible exclusions.
- **`apple-documentation-strategy.md`** — what to document (and what not), DocC discipline (summary line, `- Parameter`/`- Returns`/`- Throws`, double-backtick symbol linking, `## Topics` organization), deprecation discipline with mandatory migration paths, when to write a DocC Article vs. a doc comment.
- **`apple-localization-best-practices.md`** — String Catalogs (`.xcstrings`) as the modern format, type-safe `Strings` enum facade pattern, `LocalizedStringResource` over `NSLocalizedString`, plurals, locale-aware `.formatted()` for numbers/dates/currency, RTL via leading/trailing modifiers, translator-context comments.
- **`apple-spm-package-conventions.md`** — `Package.swift` authoring: `swift-tools-version` discipline, mandatory `platforms:`, flat per-module folder layout (`{Module}/Sources/` + `{Module}/Tests/`, matching KozBon and BasicSwiftUtilities), `makeTargets()` helper for many similar modules with `hasTests` / `hasResources` / `plugins` toggles, resources (`.process` vs `.copy`), build plugins (SwiftLintPlugins, swift-docc-plugin), `Package.resolved` discipline (commit for apps, gitignore for libraries), local-path overrides for sibling-package development, modern features (`InternalImportsByDefault`, `.swiftLanguageMode(.v6)`, `public import`), dependency hygiene (`from:` vs `exact:`).
- **`swift-concurrency-pro` skill** — reviews async/await, actors, structured concurrency.
- **`swift-testing-pro` skill** — writes and migrates tests to Swift Testing.
- **`swiftui-pro` skill** — reviews SwiftUI for modern APIs and a11y compliance.
- **`coredata-swift6-pro` skill** — Core Data under Swift 6 strict concurrency, `viewContext`/`@MainActor`, SPM `.xcdatamodeld` caveats.
- **`swift-docc-pro` skill** — DocC comment review: parameter/return/throws tags, double-backtick symbol linking, Topics organization.
- **`swift-error-handling-pro` skill** — typed throws, Result vs throws, `LocalizedError`, Sendable errors, async propagation.
- **`swift-logging-pro` skill** — `os.Logger` review: subsystem/category conventions, privacy markers, log-level semantics.
- **`swift-package-pro` skill** — SPM library design: public API surface, `InternalImportsByDefault`, resources, versioning, dependency hygiene.

### Android

- **`android-project-rules.md`** — Kotlin, Jetpack Compose, MVVM, Hilt, StateFlow, Retrofit/Moshi, ktlint.
- **`android-coroutines-best-practices.md`** — structured concurrency, scope discipline (`viewModelScope`/`lifecycleScope`, no `GlobalScope`), dispatcher choice, `Flow`/`StateFlow`/`SharedFlow` exposure, cancellation safety.
- **`android-compose-best-practices.md`** — state hoisting, side effects (`LaunchedEffect`/`DisposableEffect`/`SideEffect`), `Modifier` ordering, recomposition stability (`@Stable`/`@Immutable`), lifecycle-aware `collectAsStateWithLifecycle()`, `LazyColumn` keys.
- **`android-accessibility-best-practices.md`** — TalkBack semantics, 48dp touch targets, dynamic text, WCAG AA contrast, reduce-motion.
- **`android-testing-strategy.md`** — test pyramid, source-set discipline (`src/test` vs `src/androidTest`), `runTest` + `StandardTestDispatcher` patterns, Turbine for `Flow`, Compose UI tests via semantics (not visible text), Hilt test modules, MockK conventions, JaCoCo coverage gates with generated-code exclusions.
- **`android-documentation-strategy.md`** — KDoc syntax (`@param` / `@return` / `@throws` / `@property` / `@sample` / `@see`), Composable docs (state hoisting, semantics, skippable vs. restartable), Hilt module docs, suspend / cancellation behavior, deprecation with `ReplaceWith`, Dokka conventions and external links.
- **`android-localization-best-practices.md`** — `strings.xml` discipline, `stringResource` / `pluralStringResource` in Compose, positional format args (`%1$s` not `%s`), `<plurals>` with `getQuantityString`, locale-aware `NumberFormat` / `DateTimeFormatter`, RTL with `start`/`end` modifiers and `android:supportsRtl="true"`, translator-context comment blocks.
- **`android-gradle-conventions.md`** — Kotlin DSL only, version catalogs (`gradle/libs.versions.toml`) as single source of truth, AGP/Kotlin/Compose-compiler co-versioning, `jvmToolchain`, `api` vs `implementation`, multi-module graph patterns (`:app` + `:feature:*` + `:data:*` + `:core:*`), library publishing with `consumer-rules.pro`, KSP over kapt. **Now includes** an inline-strings → catalog migration walkthrough for legacy projects.
- **`android-gradle-architecture-pro` skill** — reviews multi-module Android builds against the **Now in Android** convention-plugin pattern: `build-logic/convention/` factoring, version-catalog depth, AGP co-versioning, KSP-over-kapt migration.
- **`xml-to-compose-migration-pro` skill** — reviews and assists XML/Fragment → Compose migration: incremental interop via `ComposeView` / `AndroidView`, layout translation (LinearLayout/ConstraintLayout/FrameLayout → Modifier), RecyclerView → `LazyColumn` with stable keys, Fragment → Composable, Navigation Component → Navigation-Compose, ViewModel bridging, themes/styles → `MaterialTheme`.
- **`r8-shrink-pro` skill** — reviews R8 / ProGuard configuration: `-keep` rule discipline, `consumer-rules.pro` contract for libraries, common reflection-library rules (Moshi, Room, Retrofit, Hilt, Glide, kotlinx-serialization), mapping-file workflow, debugging release-build crashes.

### Cross-platform

- **`project-documentation.md`** — README structure, [Keep a Changelog](https://keepachangelog.com) format, `CONTRIBUTING.md` essentials, ADR conventions (`docs/adr/####-title.md`, immutable once accepted), inline-comment philosophy (*why* not *what*), and link-rot defenses (pinned versions, permalinked source). Scoped to `README.md` / `CHANGELOG.md` / `CONTRIBUTING.md` / `docs/**/*.md`.

### Baseline

- **`settings.json`** — safe defaults for `xcodebuild`, `swift`, `swiftlint`, `./gradlew`, `gradle`, `ktlint`, `adb`, `git`, `gh`, plus Apple/Android docs domains for `WebFetch`.
- **`.gitignore`** — recommended entries for Xcode, SPM, CocoaPods, Carthage, fastlane, plus Gradle/Android Studio/Kotlin.
- **`install.sh`** — one-command bootstrap into any target repo. Flags:
  - `--platform apple|android|both`
  - `--apple-language swift|objc|both` (legacy ObjC projects skip Swift-only rules)
  - `--features all|recommended|<csv>` — **default `recommended`** is a curated subset for most apps; `all` adds specialized opt-ins (`persistence`, `ai`, `migration`, `shrinking`); custom CSVs like `core,testing,docs` give fine-grained control
  - `--list` previews the catalog with one-line descriptions + category tags
  - `--list --json` emits the same catalog as machine-readable JSON (used by the MCP server)
  - `--dry-run` shows what an install would do without writing any files
  - `--help` documents every flag and enumerates all 13 categories
  - Every install writes a manifest at `.claude/.appbootstrap-manifest.json` (groundwork for future `--upgrade` / `--uninstall`)
- **Three starter `CLAUDE.md` templates** — `templates/CLAUDE.template.apple.md`, `templates/CLAUDE.template.android.md`, `templates/CLAUDE.template.md` (cross-platform). The installer picks the right one based on `--platform`.
- **`templates/Package.template.swift`** — starter Swift Package Manager manifest with a `makeTargets(name:dependencies:hasTests:hasResources:testDependencies:testResources:)` helper. Adding a new module is a two-line change: one line in `products:` and one `+ makeTargets(...)` block in `targets:`. Copy it into a new SPM package as `Package.swift` and fill in the placeholders.

### Recommended companion tooling (optional)

- **[XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP)** — community MCP server that lets Claude drive Xcode: build schemes, run simulators, capture logs. Useful when you want the agent to verify changes against real builds and tests instead of guessing at outcomes. Especially valuable for legacy / mixed-language Apple codebases.
- **Cross-tool rule sync** — for teams running Cursor, Gemini CLI, Kiro, Copilot, Codex, or other agents alongside Claude Code. See the dedicated [Using with non-Claude AI agents](#using-with-non-claude-ai-agents) section for the workflow, tool comparison, and caveats.

## Quick start

From the root of a new app repo:

```bash
# Pure-Swift Apple project — installs the "recommended" feature set by default
/path/to/AppBootstrapAI/install.sh . --platform apple

# Android project (Kotlin + Compose)
/path/to/AppBootstrapAI/install.sh . --platform android

# Cross-platform monorepo (one repo with both)
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

# Full help — documents --features categories
/path/to/AppBootstrapAI/install.sh --help
```

Every real install writes a manifest at `.claude/.appbootstrap-manifest.json` listing every file that was installed plus the flags used. This will be the foundation for future `--upgrade` / `--uninstall` flows.

**The default `--features recommended` set** covers what most apps need on day one: `core` (project docs) + `concurrency` + `ui` + `testing` + `docs` (code documentation) + `error-handling` + `packaging` + `logging` + `localization`. Specialized opt-ins not in `recommended`: `persistence` (Core Data), `ai` (Foundation Models, iOS 26+), `migration` (XML → Compose), `shrinking` (R8/ProGuard).

The installer:

- Copies skills matching the platform/language/features intersection (Android skills under `--platform android` or `both`; Apple skills under `--platform apple` or `both` and `--apple-language` permitting Swift).
- Copies platform-matching `.claude/rules/` filtered by `--features`.
- Copies `.claude/settings.json` (only if one doesn't already exist).
- Renders the **platform-appropriate** `CLAUDE.template.*.md` into `CLAUDE.md` (only if missing): `apple` → `CLAUDE.template.apple.md`, `android` → `CLAUDE.template.android.md`, `both` → `CLAUDE.template.md`.
- Appends platform-specific entries to `.gitignore`, deduped by marker.
- Writes `.claude/.appbootstrap-manifest.json` recording every installed file (groundwork for future `--upgrade` / `--uninstall`).

It never overwrites an existing `CLAUDE.md` or `settings.json` — it prints what it skipped so you can merge.

`--dry-run` skips every write but still prints what would happen, so you can preview before committing to an upgrade.

After install, edit the new `CLAUDE.md` and fill in the `<PLACEHOLDER>` sections. Keep the `.claude/rules/` and `.claude/skills/` as-is unless you need to extend them.

> **Using a different agent?** See [Using with non-Claude AI agents](#using-with-non-claude-ai-agents) — `install.sh` lays down the Claude-native bundle, and a sync tool (`ruler` / `block/ai-rules`) fans the rules out to Cursor, Gemini CLI, Kiro, Copilot, Codex, and others.

## How it fires

**Rules** (`.claude/rules/`) load automatically based on each file's `globs:` frontmatter — Apple rules fire on `*.swift` / `*.{h,m,mm}`, Android rules fire on `*.{kt,kts}` (plus `*.xml` for the localization rule). No invocation needed; they steer Claude as soon as a matching file enters context.

**Skills** (`.claude/skills/`) are deeper review agents that fire on demand. Trigger by description match or invoke explicitly:

- "Use `swift-concurrency-pro` to review `NetworkClient.swift`."
- "Use `swiftui-pro` to check `SettingsView.swift` for modern API and a11y."
- "Use `swift-testing-pro` to write tests for `UserSession`."
- "Use `coredata-swift6-pro` to review `PersistenceController.swift`."
- "Use `swift-docc-pro` to review the public API in `MyPackage`."
- "Use `swift-error-handling-pro` to review my typed throws migration."
- "Use `swift-logging-pro` to audit `Logger` usage across the project."
- "Use `swift-package-pro` to review `Package.swift` and the public API surface."
- "Use `android-gradle-architecture-pro` to review my multi-module Gradle setup."
- "Use `xml-to-compose-migration-pro` to plan migrating `SettingsFragment` to Compose."
- "Use `r8-shrink-pro` to audit my `proguard-rules.pro` for the next release."

Each produces a file-by-file findings report with before/after fixes and a prioritized summary.

## Using AI to install

`install.sh` is a shell command — every coding agent can run it. If you'd rather *ask* the agent to bootstrap your repo than run the script by hand, three things make that work well:

1. **Hand the agent this repo's URL and your project description.** Most agents need just enough context to pick the right flags. A prompt like *"Bootstrap this iOS+macOS app with AppBootstrapAI — Swift only, include the AI/Foundation Models category"* tells Claude / Cursor / Gemini / Kiro / Copilot what they need to know.
2. **The agent can introspect the catalog before installing.** `./install.sh --list --features all` prints every rule and skill with its category and one-line description. Agents that read the output can recommend the right `--features` list for your project.
3. **For Claude Code users who want first-class integration**, this repo ships an [MCP server](mcp-server/README.md) that exposes the installer as five structured tools: `list_categories`, `list_rules`, `list_skills`, `preview_install`, and `install`. Once configured in `.claude/settings.json`, Claude can run the installer through a typed API rather than parsing shell output. See [`mcp-server/`](mcp-server/) for setup.

**Recommended prompts** (copy-paste-friendly for the agent of your choice):

| Goal | Prompt |
|------|--------|
| Bootstrap a new Apple SwiftUI app with the recommended set | *"Run `/path/to/AppBootstrapAI/install.sh . --platform apple` in this directory, then walk me through what landed."* |
| Bootstrap an Android Compose app with everything | *"Run `/path/to/AppBootstrapAI/install.sh . --platform android --features all` and summarize the new files."* |
| Pick categories interactively | *"Show me `./install.sh --list --features all`, then ask me which categories to install."* |
| Cross-platform monorepo with specific features | *"Bootstrap this repo for both Apple (Swift) and Android. Include `core`, `testing`, `docs`, `concurrency`, `ui`, and `localization`."* |
| Mixed-language Apple project (Swift + ObjC) | *"Run `./install.sh . --platform apple --apple-language both --features all`."* |

Agents that run in a terminal context (Claude Code, Cursor's agent mode, Gemini CLI, Kiro, Codex CLI) execute the shell command directly. Agents without shell access (Copilot Chat, web Claude.ai) can produce the command for you to run.

## Using with non-Claude AI agents

AppBootstrapAI ships in **Claude Code's** native layout: `.claude/rules/*.md` with `globs:` frontmatter, `.claude/skills/<name>/SKILL.md`, and a `CLAUDE.md` at the project root. The *content* of every rule and skill, though, is plain markdown that's relevant to any coding agent.

To use the same rules with Cursor, Gemini CLI, Kiro, Codex CLI, GitHub Copilot, Cline, Goose, Amp, Antigravity, Factory Droid, Mistral Vibe, Roo Code, Junie, Windsurf, etc., layer a dedicated **rule-sync tool** on top of the `.claude/` directory this bundle installs:

| Tool | Approach |
|------|----------|
| **[`ruler`](https://github.com/intellectronica/ruler)** | Reads from a unified source (you can point it at `.claude/rules/`) and applies the same rules to every supported agent's expected path on `ruler apply`. Maintains the per-tool path matrix for you. |
| **[`block/ai-rules`](https://github.com/block/ai-rules)** | Manages rules, commands, and skills across Claude, Cline, Codex, Copilot, Cursor, Firebender, Gemini, Goose, Kilocode, Roo. Installs via `curl` to `~/.local/bin/ai-rules`. |
| **[`lbb00/ai-rules-sync`](https://github.com/lbb00/ai-rules-sync)** | npm-installable CLI; similar fan-out model. |

Typical workflow:

```bash
# 1. Bootstrap the .claude/ bundle in your repo (the AppBootstrapAI half)
/path/to/AppBootstrapAI/install.sh . --platform apple

# 2. Install a sync tool of your choice (see its README for the exact command)
npm i -g @intellectronica/ruler                        # for ruler
# or: curl -fsSL https://.../install | sh              # for block/ai-rules

# 3. Point the sync tool at .claude/ and fan rules out
ruler apply                                            # ruler reads its config and writes per-agent files
# or: ai-rules sync                                     # block/ai-rules
```

**Why we don't bundle this directly:** per-tool config conventions (`.cursor/rules/*.mdc`, `GEMINI.md`, `.kiro/steering/`, `.copilot/`, etc.) shift faster than this package ships. The sync tools above track those conventions as their primary product. Reimplementing the path matrix in `install.sh` would silently rot; deferring to maintained tooling doesn't.

**Practical notes for adopters:**

- **Skills don't translate 1:1.** Claude Code's skill mechanism (procedural instructions + reference files, loaded on-demand via the Skill tool) is distinct from Cursor's `.cursor/commands/`, Gemini's prompts, and others. Sync tools generally translate *rules* faithfully; *skills* may flatten into prompts or skip entirely. Verify with your sync tool's docs.
- **`CLAUDE.md` has analogues.** Cursor reads `.cursorrules`, Gemini reads `GEMINI.md`, Codex reads `AGENTS.md`. Most sync tools generate these from your `CLAUDE.md`.
- **Project-specific overrides** (rules and skills you add for *your* app) ride along automatically — the sync tool doesn't care whether a `.claude/rules/<file>.md` came from AppBootstrapAI or from you.

## Repo layout

```
.
├── .claude/
│   ├── rules/
│   │   ├── android-accessibility-best-practices.md    # Android a11y
│   │   ├── android-compose-best-practices.md          # Jetpack Compose patterns
│   │   ├── android-coroutines-best-practices.md       # Structured concurrency
│   │   ├── android-documentation-strategy.md          # KDoc strategy + Dokka
│   │   ├── android-gradle-conventions.md              # Gradle DSL, version catalogs, modules
│   │   ├── android-localization-best-practices.md     # strings.xml, plurals, RTL
│   │   ├── android-project-rules.md                   # Kotlin/Compose/MVVM/Hilt
│   │   ├── android-testing-strategy.md                # Android test strategy + JaCoCo
│   │   ├── apple-accessibility-best-practices.md      # SwiftUI a11y
│   │   ├── apple-documentation-strategy.md            # DocC strategy + deprecation
│   │   ├── apple-foundation-models.md                 # On-device LLM patterns
│   │   ├── apple-localization-best-practices.md       # String Catalogs, plurals, RTL
│   │   ├── apple-objc-accessibility-best-practices.md # UIKit a11y in ObjC
│   │   ├── apple-objc-best-practices.md               # Modern Objective-C
│   │   ├── apple-spm-package-conventions.md           # Package.swift authoring
│   │   ├── apple-swift6-strict-concurrency.md         # Swift 6.2 strict concurrency
│   │   ├── apple-swiftui-mvvm.md                      # SwiftUI MVVM conventions
│   │   ├── apple-testing-strategy.md                  # Apple test strategy + coverage
│   │   └── project-documentation.md                   # README/CHANGELOG/ADR/inline comments
│   ├── skills/                        # On-demand skills
│   │   ├── android-gradle-architecture-pro/    # NiA-style conventions + version catalogs
│   │   ├── coredata-swift6-pro/
│   │   ├── r8-shrink-pro/                      # ProGuard/R8 rules
│   │   ├── swift-concurrency-pro/
│   │   ├── swift-docc-pro/
│   │   ├── swift-error-handling-pro/
│   │   ├── swift-logging-pro/
│   │   ├── swift-package-pro/
│   │   ├── swift-testing-pro/
│   │   ├── swiftui-pro/
│   │   └── xml-to-compose-migration-pro/       # XML/Fragment → Compose migration
│   └── settings.json                  # Baseline permissions
├── templates/
│   ├── CLAUDE.template.apple.md       # Starter for Apple-only projects
│   ├── CLAUDE.template.android.md     # Starter for Android-only projects
│   ├── CLAUDE.template.md             # Starter for cross-platform projects
│   └── Package.template.swift         # Starter Package.swift with makeTargets() helper
├── mcp-server/                        # MCP server wrapping install.sh as typed tools
│   ├── src/index.ts                   # 5 tools: list_categories/rules/skills, preview_install, install
│   ├── package.json
│   └── README.md                      # MCP setup instructions for Claude Code / Cursor / others
├── install.sh                         # One-command bootstrap
├── CLAUDE.md                          # This repo's own AI onboarding
├── LICENSE                            # MIT
└── README.md
```

## Extending for your project

See [CLAUDE.md](CLAUDE.md) for:

- Writing new rules (`.claude/rules/<name>.md` with frontmatter `description` + `globs`).
- Writing new skills (`.claude/skills/<name>/SKILL.md` + `references/` for deep context).
- Recommended project-specific additions (swiftlint config, CI, localization).

## Roadmap

- **Skills exist for both Apple and Android.** Apple has 8 skills (concurrency, testing, SwiftUI, Core Data, DocC, error handling, logging, SPM); Android has 3 (Gradle architecture, XML-to-Compose migration, R8/ProGuard). Android skill coverage will grow as production patterns surface — Compose-pro and coroutines-pro equivalents of the Apple skills are on the roadmap.
- All rules (Apple + Android) are loaded automatically by `globs` and apply equally; there is no "primary" / "secondary" platform in the bundle's design.

## Credits

- Apple skills authored by **Paul Hudson** ([@twostraws](https://github.com/twostraws)) and licensed MIT. Original sources, linked from the bundled skill references:
  - [`swift-concurrency-agent-skill`](https://github.com/twostraws/swift-concurrency-agent-skill)
  - [`swift-testing-agent-skill`](https://github.com/twostraws/swift-testing-agent-skill)
  - [`swiftui-agent-skill`](https://github.com/twostraws/swiftui-agent-skill)
  - [`swiftdata-agent-skill`](https://github.com/twostraws/swiftdata-agent-skill)
  - …and more on his profile. Author attribution is retained in each `SKILL.md` frontmatter.
- Android skills (`android-gradle-architecture-pro`, `xml-to-compose-migration-pro`, `r8-shrink-pro`) authored by AppBootstrapAI contributors. Grounded in [Android's Now in Android](https://github.com/android/nowinandroid) reference app and the official [Android Developers documentation](https://developer.android.com/build) for AGP, Compose, and R8 — the canonical primary sources. Licensed MIT.

## License

MIT — see [LICENSE](LICENSE).
