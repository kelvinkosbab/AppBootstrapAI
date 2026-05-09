# AppBootstrapAI

A drop-in bundle of **Claude Code skills** and **AI steering rules** for bootstrapping new app projects. Primary focus is Apple platforms (iOS, macOS, tvOS, watchOS, visionOS); Android guidance is included as a secondary target so mixed-stack teams can share one source of truth.

This repo is not a Swift package — it's a curated `.claude/` directory plus onboarding docs, distilled from production use across the Kozinga app projects. Copy it into any new app and Claude Code picks up consistent review, testing, and style guidance on day one.

## What you get

### Apple (primary)

- **`apple-swift6-strict-concurrency.md`** — Swift 6.2 strict concurrency, enforced on every `.swift` file.
- **`apple-accessibility-best-practices.md`** — VoiceOver, Dynamic Type, Reduce Motion for SwiftUI (including streaming AI text).
- **`apple-foundation-models.md`** — Apple Foundation Models patterns: session ownership, two-level availability gating, streaming placeholder-then-mutate, `Task.isCancelled` discipline, protocol + mock + simulator testability.
- **`apple-swiftui-mvvm.md`** — SwiftUI MVVM conventions: when to extract a view model, `@State` vs `@Bindable` ownership, dependency plumbing, what stays on the View vs the view model, splitting large VMs across extension files.
- **`apple-objc-best-practices.md`** — Modern Objective-C for legacy / mixed-language codebases: ARC discipline, nullability, lightweight generics, `instancetype`, designated initializers, modern literals/blocks, Swift bridging-header conventions.
- **`apple-testing-strategy.md`** — what to test (and what not), Given/When/Then naming, determinism (inject clocks/UUIDs/network), Swift Testing vs XCTest split, XCUITest discipline, CI coverage gates with sensible exclusions.
- **`swift-concurrency-pro` skill** — reviews async/await, actors, structured concurrency.
- **`swift-testing-pro` skill** — writes and migrates tests to Swift Testing.
- **`swiftui-pro` skill** — reviews SwiftUI for modern APIs and a11y compliance.
- **`coredata-swift6-pro` skill** — Core Data under Swift 6 strict concurrency, `viewContext`/`@MainActor`, SPM `.xcdatamodeld` caveats.
- **`swift-docc-pro` skill** — DocC comment review: parameter/return/throws tags, double-backtick symbol linking, Topics organization.
- **`swift-error-handling-pro` skill** — typed throws, Result vs throws, `LocalizedError`, Sendable errors, async propagation.
- **`swift-logging-pro` skill** — `os.Logger` review: subsystem/category conventions, privacy markers, log-level semantics.
- **`swift-package-pro` skill** — SPM library design: public API surface, `InternalImportsByDefault`, resources, versioning, dependency hygiene.

### Android (secondary)

- **`android-project-rules.md`** — Kotlin, Jetpack Compose, MVVM, Hilt, StateFlow, Retrofit/Moshi, ktlint.
- **`android-coroutines-best-practices.md`** — structured concurrency, scope discipline (`viewModelScope`/`lifecycleScope`, no `GlobalScope`), dispatcher choice, `Flow`/`StateFlow`/`SharedFlow` exposure, cancellation safety.
- **`android-compose-best-practices.md`** — state hoisting, side effects (`LaunchedEffect`/`DisposableEffect`/`SideEffect`), `Modifier` ordering, recomposition stability (`@Stable`/`@Immutable`), lifecycle-aware `collectAsStateWithLifecycle()`, `LazyColumn` keys.
- **`android-accessibility-best-practices.md`** — TalkBack semantics, 48dp touch targets, dynamic text, WCAG AA contrast, reduce-motion.
- **`android-testing-strategy.md`** — test pyramid, source-set discipline (`src/test` vs `src/androidTest`), `runTest` + `StandardTestDispatcher` patterns, Turbine for `Flow`, Compose UI tests via semantics (not visible text), Hilt test modules, MockK conventions, JaCoCo coverage gates with generated-code exclusions.
- *(No Android skills yet — on the roadmap.)*

### Baseline

- **`settings.json`** — safe defaults for `xcodebuild`, `swift`, `swiftlint`, `./gradlew`, `gradle`, `ktlint`, `adb`, `git`, `gh`, plus Apple/Android docs domains for `WebFetch`.
- **`.gitignore`** — recommended entries for Xcode, SPM, CocoaPods, Carthage, fastlane, plus Gradle/Android Studio/Kotlin.
- **`install.sh`** — one-command bootstrap into any target repo. Supports `--platform apple|android|both`, `--apple-language swift|objc|both` (so legacy ObjC projects don't get Swift-only rules), `--list` (preview the catalog of rules and skills with one-line descriptions), and `--help`.
- **`templates/CLAUDE.template.md`** — starter `CLAUDE.md` for the target app, with placeholders you fill in.

### Recommended companion tooling (optional)

- **[XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP)** — community MCP server that lets Claude drive Xcode: build schemes, run simulators, capture logs. Useful when you want the agent to verify changes against real builds and tests instead of guessing at outcomes. Especially valuable for legacy / mixed-language Apple codebases.

## Quick start

From the root of a new app repo:

```bash
# One-command install (recommended)
/path/to/AppBootstrapAI/install.sh . --platform apple    # or: android | both

# Apple-side, Objective-C only (legacy projects)
/path/to/AppBootstrapAI/install.sh . --platform apple --apple-language objc

# Apple-side, Swift + ObjC (mixed-language projects)
/path/to/AppBootstrapAI/install.sh . --platform apple --apple-language both

# See exactly what would be installed for any flag combination
/path/to/AppBootstrapAI/install.sh --list --platform apple --apple-language swift

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

## Invoking the skills

Skills auto-trigger when their description matches. You can also invoke explicitly:

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
│   │   ├── android-project-rules.md                   # Kotlin/Compose/MVVM/Hilt
│   │   ├── android-testing-strategy.md                # Android test strategy + JaCoCo
│   │   ├── apple-accessibility-best-practices.md      # SwiftUI a11y
│   │   ├── apple-foundation-models.md                 # On-device LLM patterns
│   │   ├── apple-objc-best-practices.md               # Modern Objective-C
│   │   ├── apple-swift6-strict-concurrency.md         # Swift 6.2 strict concurrency
│   │   ├── apple-swiftui-mvvm.md                      # SwiftUI MVVM conventions
│   │   └── apple-testing-strategy.md                  # Apple test strategy + coverage
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

- Apple-side skills and rules are production-tested.
- Android support is currently **rules-only** — Kotlin/Compose skills (equivalents of `swiftui-pro` et al.) are not yet included.

## Credits

- Skills authored by **Paul Hudson** (MIT). Retained with author attribution in each `SKILL.md`.
- Steering rules and onboarding structure adapted from **KozBon** and **BasicSwiftUtilities**.

## License

MIT — see [LICENSE](LICENSE).
