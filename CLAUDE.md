# CLAUDE.md

## Project Overview

**AppBootstrapAI** is a drop-in bundle of Claude Code skills and AI steering rules for bootstrapping new app projects. Primary focus is Apple platforms (iOS, macOS, tvOS, watchOS, visionOS) with Swift 6.2 concurrency, SwiftUI, and Swift Testing guidance. Secondary focus is Android (Kotlin, Jetpack Compose, MVVM, Hilt) — rules only for now, no dedicated skills yet.

This repo is **not** a Swift package. It is a collection of `.claude/` assets intended to be copied (or referenced) into a target app repository so that Claude Code picks up consistent review, testing, and style guidance across projects.

## What's in the box

```
.claude/
├── rules/                         # Always-loaded AI steering (Cursor-style rule files)
│   ├── android-accessibility-best-practices.md    # Android: TalkBack / Compose semantics
│   ├── android-compose-best-practices.md          # Android: Jetpack Compose patterns
│   ├── android-coroutines-best-practices.md       # Android: Kotlin coroutines / structured concurrency
│   ├── android-project-rules.md                   # Android: Kotlin/Compose/MVVM/Hilt
│   ├── android-testing-strategy.md                # Android: test strategy + JaCoCo
│   ├── apple-accessibility-best-practices.md      # Apple: SwiftUI a11y
│   ├── apple-foundation-models.md                 # Apple: On-device LLM (FoundationModels)
│   ├── apple-objc-best-practices.md               # Apple: Modern Objective-C
│   ├── apple-swift6-strict-concurrency.md         # Apple: Swift 6.2 strict concurrency
│   ├── apple-swiftui-mvvm.md                      # Apple: SwiftUI MVVM conventions
│   └── apple-testing-strategy.md                  # Apple: test strategy + coverage
├── skills/                        # On-demand Claude Code skills (Apple-only today)
│   ├── coredata-swift6-pro/       # Core Data under Swift 6 strict concurrency
│   ├── swift-concurrency-pro/     # Reviews Swift concurrency correctness
│   ├── swift-docc-pro/            # Reviews DocC documentation comments
│   ├── swift-error-handling-pro/  # Typed throws, Result, LocalizedError
│   ├── swift-logging-pro/         # os.Logger review (privacy, levels, subsystems)
│   ├── swift-package-pro/         # SPM library design and API hygiene
│   ├── swift-testing-pro/         # Writes/reviews Swift Testing code
│   └── swiftui-pro/               # Reviews SwiftUI for modern APIs and a11y
└── settings.json                  # Baseline Claude Code permissions (git, xcodebuild, gradlew, etc.)
```

Plus, at the repo root:

- `install.sh` — one-command bootstrap into any target repo (`--platform apple|android|both`).
- `templates/CLAUDE.template.apple.md` — starter `CLAUDE.md` for Apple-only projects.
- `templates/CLAUDE.template.android.md` — starter `CLAUDE.md` for Android-only projects.
- `templates/CLAUDE.template.md` — starter `CLAUDE.md` for cross-platform projects.

The installer picks the right template based on `--platform`.

Each skill ships with:

- `SKILL.md` — the skill's entry point and review checklist (loaded when the skill is invoked).
- `references/` — topic-specific deep-dive notes the skill loads on demand.
- `agents/openai.yaml` — interface metadata (display name, icon, default prompt).
- `assets/` — SVG/PNG icons for the skill.

## How to onboard this into a new app project

Use the installer from the target repo:

```bash
# Pure-Swift Apple project (default)
/path/to/AppBootstrapAI/install.sh . --platform apple

# Legacy / Objective-C only
/path/to/AppBootstrapAI/install.sh . --platform apple --apple-language objc

# Mixed-language Apple project
/path/to/AppBootstrapAI/install.sh . --platform apple --apple-language both

# Android
/path/to/AppBootstrapAI/install.sh . --platform android

# Cross-platform (one repo with both)
/path/to/AppBootstrapAI/install.sh . --platform both

# Preview the rules and skills that any flag combo would install
/path/to/AppBootstrapAI/install.sh --list --platform apple --apple-language swift

# Full help
/path/to/AppBootstrapAI/install.sh --help
```

The installer copies skills (when Swift is in scope), platform-matching rules, settings, the platform-appropriate starter `CLAUDE.md`, and appends `.gitignore` entries. It never overwrites existing `CLAUDE.md` or `settings.json` — it prints what it skipped.

Then customize the new repo's `CLAUDE.md` to describe **that** project's specifics: modules, build commands, dependency graph, gotchas. Keep the steering rules and skills as-is — they apply to any modern Apple or Android app.

## Invoking the skills

Skills auto-trigger when the description matches the task. You can also invoke them explicitly:

- "Use `swift-concurrency-pro` to review the changes in `NetworkClient.swift`."
- "Use `swiftui-pro` to review `SettingsView.swift` for modern API and a11y."
- "Use `swift-testing-pro` to write tests for `UserSession`."
- "Use `coredata-swift6-pro` to review the persistence layer."
- "Use `swift-docc-pro` to review documentation in this package."
- "Use `swift-error-handling-pro` to review error types and throwing functions."
- "Use `swift-logging-pro` to audit Logger usage."
- "Use `swift-package-pro` to review `Package.swift` and the public API."

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

### SwiftUI MVVM conventions (`apple-swiftui-mvvm.md`)

- Extract a view model when the View has business logic, multi-step async, 5+ interacting `@State`, needs unit-testing, or is split across extension files.
- View models are `@MainActor @Observable final class` with state + long-lived deps captured at init.
- Choose ownership by lifecycle: `@State` (per-view) vs `@Bindable` (shared when two instances would race over a single resource — delegate slots, scans, persistent connections).
- View models stay free of `@Environment` and `Binding<T>`. Pass environment values into methods as parameters.
- View keeps `@FocusState`, `@Environment` reads, pure UI flags, and SwiftUI-specific bindings; the view model holds everything else.
- Split large VMs into `+Send.swift`/`+Scroll.swift`/`+Intents.swift` extension files; use `internal` for cross-file helpers, `private` only for in-file helpers.

### Apple Foundation Models (`apple-foundation-models.md`)

- Session holders are `@MainActor @Observable final class` — never structs, views, or background actors.
- Keep one `LanguageModelSession` alive per conversation; only recreate on config change (document that history is lost).
- Gate at two levels: `SystemLanguageModel.default.availability` (handle each `.unavailable(_)` reason distinctly) AND a user preference.
- Streaming pattern: append placeholder → mutate in place → remove on error. Check `Task.isCancelled` inside the loop; `defer { isGenerating = false }` at function top.
- Catch errors broadly and surface `error.localizedDescription`; do not pattern-match specific cases (the enum changes across OS releases).
- Testability: protocol wrapper + Real/Mock/Simulator implementations, injected via `@Environment` with lazy fallback. Real impl is the only file that touches `import FoundationModels`.

### Apple test strategy & coverage (`apple-testing-strategy.md`)

- Test pyramid: bulk unit tests, fewer integration, fewest UI (XCUITest, on schedule).
- Test the *behavior* through public API; skip private impl, third-party SDKs, generated code, DI wiring.
- Name tests by behavior (`loginRejectsExpiredToken`), not by method-under-test.
- Determinism is mandatory: inject clocks/UUIDs/randomness/network. No `Date()` / `UUID()` / `Thread.sleep` / live network in code under test.
- Default to Swift Testing for new tests; keep XCTest only for UI (`XCUITest`) and performance (`measure`).
- XCUITest: locate by `.accessibilityIdentifier`, never visible localized text.
- Coverage: track in CI (Slather / Codecov / `xcrun xccov`), set a *policy* gate (commonly 70–80%), exclude generated code, DI, model-only types, and `@main`. Coverage is a hint, not a goal — don't game it.

### Modern Objective-C (`apple-objc-best-practices.md`)

Scoped to `**/*.{h,m,mm}`. Encodes the evergreen modern-ObjC patterns:

- **ARC only.** No manual `retain`/`release`/`autorelease`. `__weak`/`__strong` dance for blocks. `@autoreleasepool { }` in long allocating loops.
- **Nullability everywhere.** `NS_ASSUME_NONNULL_BEGIN`/`END` wrapping every header; explicit `nullable` annotations; `NS_NOESCAPE` on non-escaping block parameters.
- **Type system.** `instancetype` not `id`; lightweight generics on collections; forward-declare with `@class`/`@protocol` in headers.
- **Properties.** Prefer over ivars; explicit ownership (`copy` for strings/arrays/blocks); `nonatomic` default; class extensions for private API.
- **Initializers.** `NS_DESIGNATED_INITIALIZER` + `NS_UNAVAILABLE` on inherited inits. Never call subclassable methods inside `-init`/`-dealloc`.
- **Modern syntax.** Literal/subscript syntax; `typedef`'d block types; `-isEqualToString:` not `==`; `#pragma mark - Section` for organization.
- **Swift interop.** Bridging-header discipline; `NS_SWIFT_NAME(...)` to control names; `NS_REFINED_FOR_SWIFT` to wrap raw APIs.

## Working with AI on legacy / mixed-language Apple codebases

When a project mixes Swift and Objective-C (or has any sizable ObjC surface area), a few workflow disciplines keep AI agents from making things worse:

- **Refactor in small scopes.** Ask Claude to refactor a single method or a single file at a time, not "modernize the whole module." Large, unbounded refactors mix unrelated concerns and produce diffs that are hard to review.
- **Don't paste the full build log on failures.** Paste the failing function name, the specific compiler error lines (typically 5–20), and the immediately surrounding source. Pasting hundreds of lines of unrelated warnings drowns the actual signal and inflates context.
- **Be explicit about bridging-header changes.** When adding a new ObjC class that Swift needs to call, say so: *"Add `MyService.h` to `<ProjectName>-Bridging-Header.h`."* Claude will not infer this from context — and a missing import causes "Cannot find type" errors that look unrelated.
- **State the language explicitly when ambiguous.** *"Implement `MyViewController` in Objective-C, not Swift"* — file extensions disambiguate but prompt phrasing sometimes doesn't.
- **Verify against the actual toolchain, not my training data.** If you ask Claude about a specific Xcode menu path, simulator behavior, or new SDK API, treat the answer as a starting point — confirm in Xcode itself before encoding it as a rule. The package's value is that its rules are ground truth.
- **Optional companion tooling:** [`XcodeBuildMCP`](https://github.com/cameroncooke/XcodeBuildMCP) is a community MCP server that lets agents drive Xcode (build schemes, simulators, log capture). Useful when you want Claude to run real builds and tests instead of guessing at outcomes.

### Android project rules (`android-project-rules.md`)

Scoped to `**/*.{kt,kts}`. Encodes:

- **Stack:** Kotlin + Jetpack Compose (no XML), MVVM, Hilt DI, StateFlow + `collectAsStateWithLifecycle()`, Retrofit + Moshi.
- **Style:** ktlint, `PascalCase` Composables, `camelCase` members, no wildcard imports.
- **Workflow:** `./gradlew assembleDebug | test | ktlintCheck` (run ktlint before every commit).
- **Safety:** never hardcode secrets; all UI text in `strings.xml`.

### Kotlin coroutines (`android-coroutines-best-practices.md`)

- Right scope for the lifetime: `viewModelScope` for VMs, `lifecycleScope` for UI, `WorkManager` for process-death-surviving work. Never `GlobalScope`. Never `runBlocking` in app code.
- Dispatchers: `Main` for UI, `IO` for blocking I/O, `Default` for CPU. Inject dispatchers so tests can substitute.
- Cancellation is cooperative — never catch `CancellationException`; use `try { } finally { }` for cleanup.
- `Flow` (cold) / `StateFlow` (hot value-holding) / `SharedFlow` (hot one-shot). Expose read-only base types from VMs.
- Always `collectAsStateWithLifecycle()` in Compose — never raw `collectAsState()`.
- `supervisorScope` / `SupervisorJob` for sibling-failure isolation. `CoroutineExceptionHandler` for top-level uncaught.

### Jetpack Compose (`android-compose-best-practices.md`)

- State hoisting: stateless Composables receive `value` + `onValueChange`; stateful wrappers read from VMs.
- `remember` for in-composition state; `rememberSaveable` for config-change survivable state. Business state lives in VMs, never in `remember`.
- Side effects in their proper wrappers: `LaunchedEffect`, `DisposableEffect`, `SideEffect`, `rememberCoroutineScope`, `produceState`. Never start work directly in the Composable body.
- `@Stable` / `@Immutable` on data flowing into Composables to enable skippable composition. `kotlin.collections.List` is *not* stable by default — use `ImmutableList` or annotate the holder.
- `Modifier` order matters: layout → drawing → input. `.padding().background()` ≠ `.background().padding()`.
- `derivedStateOf` to filter recomposition noise; stable `key` lambdas on `LazyColumn`/`LazyRow`.
- Always `collectAsStateWithLifecycle()` for `Flow`/`StateFlow`.

### Android test strategy & coverage (`android-testing-strategy.md`)

- Source-set discipline: `src/test/` for unit tests (JUnit, MockK, Turbine, optional Robolectric), `src/androidTest/` for instrumentation (Compose UI, real Room, Hilt-injected components).
- Coroutines: `runTest`, `StandardTestDispatcher` for virtual time, `UnconfinedTestDispatcher` for eager. Inject dispatchers; install/reset `Dispatchers.Main` via a `MainDispatcherRule`. Never `runBlocking` or `Thread.sleep`.
- `Flow`/`StateFlow` testing: Turbine `.test { awaitItem(); awaitComplete() }`; close every flow with `awaitComplete()` / `cancelAndIgnoreRemainingEvents()`.
- Compose UI: locate by `testTag` / `contentDescription` (semantics), never visible localized text. Use `waitForIdle` / `waitUntil`, never `Thread.sleep`.
- Hilt tests: `@HiltAndroidTest`, `HiltAndroidRule`, `@UninstallModules` + `@BindValue` to swap real bindings for fakes.
- MockK: `mockk<T>()` / `coEvery` / `coVerify`; don't mock data classes — use static factory fixtures.
- Coverage: JaCoCo with a CI gate (commonly 70–80%); exclude Hilt-generated, KSP outputs, Activities/Application, Compose `@Preview`, DI modules. A failing gate or it's decorative.

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
