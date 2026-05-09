# AppBootstrapAI

A drop-in bundle of **Claude Code skills** and **AI steering rules** for bootstrapping new app projects. Covers Apple platforms (iOS, macOS, tvOS, watchOS, visionOS) and Android in one bundle, so single-platform and mixed-stack teams can share one source of truth.

This repo is not a Swift package — it's a curated `.claude/` directory plus onboarding docs. Copy it into any new app and Claude Code picks up consistent review, testing, and style guidance on day one.

## What you get

### Apple

- **`apple-swift6-strict-concurrency.md`** — Swift 6.2 strict concurrency, enforced on every `.swift` file.
- **`apple-accessibility-best-practices.md`** — VoiceOver, Dynamic Type, Reduce Motion for SwiftUI (including streaming AI text).
- **`apple-foundation-models.md`** — Apple Foundation Models patterns: session ownership, two-level availability gating, streaming placeholder-then-mutate, `Task.isCancelled` discipline, protocol + mock + simulator testability.
- **`apple-swiftui-mvvm.md`** — SwiftUI MVVM conventions: when to extract a view model, `@State` vs `@Bindable` ownership, dependency plumbing, what stays on the View vs the view model, splitting large VMs across extension files.
- **`apple-objc-best-practices.md`** — Modern Objective-C for legacy / mixed-language codebases: ARC discipline, nullability, lightweight generics, `instancetype`, designated initializers, modern literals/blocks, Swift bridging-header conventions.
- **`apple-testing-strategy.md`** — what to test (and what not), Given/When/Then naming, determinism (inject clocks/UUIDs/network), Swift Testing vs XCTest split, XCUITest discipline, CI coverage gates with sensible exclusions.
- **`apple-documentation-strategy.md`** — what to document (and what not), DocC discipline (summary line, `- Parameter`/`- Returns`/`- Throws`, double-backtick symbol linking, `## Topics` organization), deprecation discipline with mandatory migration paths, when to write a DocC Article vs. a doc comment.
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
- *(No Android skills yet — on the roadmap.)*

### Cross-platform

- **`project-documentation.md`** — README structure, [Keep a Changelog](https://keepachangelog.com) format, `CONTRIBUTING.md` essentials, ADR conventions (`docs/adr/####-title.md`, immutable once accepted), inline-comment philosophy (*why* not *what*), and link-rot defenses (pinned versions, permalinked source). Scoped to `README.md` / `CHANGELOG.md` / `CONTRIBUTING.md` / `docs/**/*.md`.

### Baseline

- **`settings.json`** — safe defaults for `xcodebuild`, `swift`, `swiftlint`, `./gradlew`, `gradle`, `ktlint`, `adb`, `git`, `gh`, plus Apple/Android docs domains for `WebFetch`.
- **`.gitignore`** — recommended entries for Xcode, SPM, CocoaPods, Carthage, fastlane, plus Gradle/Android Studio/Kotlin.
- **`install.sh`** — one-command bootstrap into any target repo. Supports `--platform apple|android|both`, `--apple-language swift|objc|both` (so legacy ObjC projects don't get Swift-only rules), `--list` (preview the catalog of rules and skills with one-line descriptions), and `--help`.
- **Three starter `CLAUDE.md` templates** — `templates/CLAUDE.template.apple.md`, `templates/CLAUDE.template.android.md`, `templates/CLAUDE.template.md` (cross-platform). The installer picks the right one based on `--platform`.

### Recommended companion tooling (optional)

- **[XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP)** — community MCP server that lets Claude drive Xcode: build schemes, run simulators, capture logs. Useful when you want the agent to verify changes against real builds and tests instead of guessing at outcomes. Especially valuable for legacy / mixed-language Apple codebases.

## Quick start

From the root of a new app repo:

```bash
# Pure-Swift Apple project
/path/to/AppBootstrapAI/install.sh . --platform apple

# Android project (Kotlin + Compose)
/path/to/AppBootstrapAI/install.sh . --platform android

# Cross-platform monorepo (one repo with both)
/path/to/AppBootstrapAI/install.sh . --platform both

# Apple legacy project — Objective-C only
/path/to/AppBootstrapAI/install.sh . --platform apple --apple-language objc

# Apple mixed-language — Swift + ObjC
/path/to/AppBootstrapAI/install.sh . --platform apple --apple-language both

# Preview what any flag combo will install (no files written)
/path/to/AppBootstrapAI/install.sh --list --platform android

# Full help
/path/to/AppBootstrapAI/install.sh --help
```

The installer:

- Copies `.claude/skills/` (when `apple` or `both`) and platform-matching `.claude/rules/`.
- Copies `.claude/settings.json` (only if one doesn't already exist).
- Renders the **platform-appropriate** `CLAUDE.template.*.md` into `CLAUDE.md` (only if missing): `apple` → `CLAUDE.template.apple.md`, `android` → `CLAUDE.template.android.md`, `both` → `CLAUDE.template.md`.
- Appends platform-specific entries to `.gitignore`, deduped by marker.

It never overwrites an existing `CLAUDE.md` or `settings.json` — it prints what it skipped so you can merge.

After install, edit the new `CLAUDE.md` and fill in the `<PLACEHOLDER>` sections. Keep the `.claude/rules/` and `.claude/skills/` as-is unless you need to extend them.

## How it fires

**Rules** (`.claude/rules/`) load automatically based on each file's `globs:` frontmatter — Apple rules fire on `*.swift` / `*.{h,m,mm}`, Android rules fire on `*.{kt,kts}`. No invocation needed; they steer Claude as soon as a matching file enters context. This is the bulk of what you get on the Android side today.

**Skills** (`.claude/skills/`) are deeper review agents that fire on demand — currently Apple-only. Trigger by description match or invoke explicitly:

- "Use `swift-concurrency-pro` to review `NetworkClient.swift`."
- "Use `swiftui-pro` to check `SettingsView.swift` for modern API and a11y."
- "Use `swift-testing-pro` to write tests for `UserSession`."
- "Use `coredata-swift6-pro` to review `PersistenceController.swift`."
- "Use `swift-docc-pro` to review the public API in `MyPackage`."
- "Use `swift-error-handling-pro` to review my typed throws migration."
- "Use `swift-logging-pro` to audit `Logger` usage across the project."
- "Use `swift-package-pro` to review `Package.swift` and the public API surface."

Each produces a file-by-file findings report with before/after fixes and a prioritized summary.

## Repo layout

```
.
├── .claude/
│   ├── rules/
│   │   ├── android-accessibility-best-practices.md    # Android a11y
│   │   ├── android-compose-best-practices.md          # Jetpack Compose patterns
│   │   ├── android-coroutines-best-practices.md       # Structured concurrency
│   │   ├── android-documentation-strategy.md          # KDoc strategy + Dokka
│   │   ├── android-project-rules.md                   # Kotlin/Compose/MVVM/Hilt
│   │   ├── android-testing-strategy.md                # Android test strategy + JaCoCo
│   │   ├── apple-accessibility-best-practices.md      # SwiftUI a11y
│   │   ├── apple-documentation-strategy.md            # DocC strategy + deprecation
│   │   ├── apple-foundation-models.md                 # On-device LLM patterns
│   │   ├── apple-objc-best-practices.md               # Modern Objective-C
│   │   ├── apple-swift6-strict-concurrency.md         # Swift 6.2 strict concurrency
│   │   ├── apple-swiftui-mvvm.md                      # SwiftUI MVVM conventions
│   │   ├── apple-testing-strategy.md                  # Apple test strategy + coverage
│   │   └── project-documentation.md                   # README/CHANGELOG/ADR/inline comments
│   ├── skills/                        # On-demand skills (Apple-only today)
│   │   ├── coredata-swift6-pro/
│   │   ├── swift-concurrency-pro/
│   │   ├── swift-docc-pro/
│   │   ├── swift-error-handling-pro/
│   │   ├── swift-logging-pro/
│   │   ├── swift-package-pro/
│   │   ├── swift-testing-pro/
│   │   └── swiftui-pro/
│   └── settings.json                  # Baseline permissions
├── templates/
│   ├── CLAUDE.template.apple.md       # Starter for Apple-only projects
│   ├── CLAUDE.template.android.md     # Starter for Android-only projects
│   └── CLAUDE.template.md             # Starter for cross-platform projects
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

- **Skills (deep-dive review agents) currently exist for Apple only.** Kotlin/Compose-side equivalents of `swiftui-pro`, `swift-concurrency-pro`, `swift-testing-pro`, etc. are not yet included — Android coverage is rules + steering for now.
- All rules (Apple + Android) are loaded automatically by `globs` and apply equally; there is no "primary" / "secondary" platform in the bundle's design — Apple-side skills are simply further along, with Android skill-equivalents (Compose-pro, coroutines-pro, etc.) on the roadmap.

## Credits

- Skills authored by **Paul Hudson** ([@twostraws](https://github.com/twostraws)) and licensed MIT. Original sources, linked from the bundled skill references and worth starring at the source:
  - [`swift-concurrency-agent-skill`](https://github.com/twostraws/swift-concurrency-agent-skill)
  - [`swift-testing-agent-skill`](https://github.com/twostraws/swift-testing-agent-skill)
  - [`swiftui-agent-skill`](https://github.com/twostraws/swiftui-agent-skill)
  - [`swiftdata-agent-skill`](https://github.com/twostraws/swiftdata-agent-skill)
  - …and more on his profile. Author attribution is retained in each `SKILL.md` frontmatter.

## License

MIT — see [LICENSE](LICENSE).
