# CLAUDE.md

## Project Overview

**AppBootstrapAI** is a drop-in bundle of Claude Code skills and AI steering rules for bootstrapping new app projects. Covers Apple platforms (iOS, macOS, tvOS, watchOS, visionOS — Swift 6.2 concurrency, SwiftUI, Swift Testing, Foundation Models, Objective-C) and Android (Kotlin, Jetpack Compose, MVVM, Hilt, coroutines) in one bundle. Skills (deep-dive review agents) currently exist for the Apple side only; Android is covered by steering rules until production patterns surface enough to harden a skill against.

This repo is **not** a Swift package. It is a collection of `.claude/` assets intended to be copied (or referenced) into a target app repository so that Claude Code picks up consistent review, testing, and style guidance across projects.

## What's in the box

```
.claude/
├── rules/                         # Always-loaded AI steering (Cursor-style rule files)
│   ├── android-accessibility-best-practices.md    # Android: TalkBack / Compose semantics
│   ├── android-compose-best-practices.md          # Android: Jetpack Compose patterns
│   ├── android-coroutines-best-practices.md       # Android: Kotlin coroutines / structured concurrency
│   ├── android-documentation-strategy.md          # Android: KDoc strategy + Dokka
│   ├── android-gradle-conventions.md              # Android: Gradle DSL / version catalogs / modules
│   ├── android-linting-strategy.md                # Android: ktlint + detekt + Android Lint
│   ├── android-localization-best-practices.md     # Android: strings.xml / plurals / RTL
│   ├── android-play-beta-deployment.md            # Android: Play beta tracks, signing, CI
│   ├── android-project-rules.md                   # Android: Kotlin/Compose/MVVM/Hilt
│   ├── android-testing-strategy.md                # Android: test strategy + JaCoCo
│   ├── apple-accessibility-best-practices.md      # Apple: SwiftUI a11y
│   ├── apple-documentation-strategy.md            # Apple: DocC strategy + deprecation
│   ├── apple-foundation-models.md                 # Apple: On-device LLM (FoundationModels)
│   ├── apple-linting-strategy.md                  # Apple: SwiftLint + formatter discipline
│   ├── apple-localization-best-practices.md       # Apple: String Catalogs / plurals / RTL
│   ├── apple-objc-accessibility-best-practices.md # Apple: UIKit a11y in Objective-C
│   ├── apple-objc-best-practices.md               # Apple: Modern Objective-C
│   ├── apple-spm-package-conventions.md           # Apple: Package.swift authoring
│   ├── apple-swift6-strict-concurrency.md         # Apple: Swift 6.2 strict concurrency
│   ├── apple-swiftui-mvvm.md                      # Apple: SwiftUI MVVM conventions
│   ├── apple-testflight-deployment.md             # Apple: TestFlight, ASC API, signing, CI
│   ├── apple-testing-strategy.md                  # Apple: test strategy + coverage
│   ├── apple-visionos-best-practices.md           # Apple: visionOS / RealityKit / spatial UX
│   └── project-documentation.md                   # Cross-platform: README/CHANGELOG/ADR
├── skills/                        # On-demand Claude Code skills
│   ├── android-gradle-architecture-pro/    # Android: NiA-style convention plugins
│   ├── coredata-swift6-pro/                # Apple: Core Data under Swift 6
│   ├── r8-shrink-pro/                      # Android: ProGuard/R8 rules
│   ├── swift-concurrency-pro/              # Apple: Swift concurrency review
│   ├── swift-docc-pro/                     # Apple: DocC documentation
│   ├── swift-error-handling-pro/           # Apple: typed throws, Result
│   ├── swift-logging-pro/                  # Apple: os.Logger review
│   ├── swift-package-pro/                  # Apple: SPM library design
│   ├── swift-testing-pro/                  # Apple: Swift Testing code
│   ├── swiftui-pro/                        # Apple: SwiftUI review
│   └── xml-to-compose-migration-pro/       # Android: XML/Fragment → Compose
└── settings.json                  # Baseline Claude Code permissions (git, xcodebuild, gradlew, etc.)
```

Plus, at the repo root:

- `install.sh` — one-command bootstrap into any target repo (`--platform apple|android|both`).
- `templates/CLAUDE.template.apple.md` — starter `CLAUDE.md` for Apple-only projects.
- `templates/CLAUDE.template.android.md` — starter `CLAUDE.md` for Android-only projects.
- `templates/CLAUDE.template.md` — starter `CLAUDE.md` for cross-platform projects.
- `templates/Package.template.swift` — starter `Package.swift` with a `makeTargets()` helper that collapses per-module boilerplate; adding a new module is a two-line change (one in `products:`, one `+ makeTargets(...)` block).

The installer picks the right `CLAUDE.md` template based on `--platform`. The `Package.template.swift` is copied manually into new SPM packages — `install.sh` doesn't drop it because the bundle target is usually an existing app, not a fresh package.

Each skill ships with:

- `SKILL.md` — the skill's entry point and review checklist (loaded when the skill is invoked).
- `references/` — topic-specific deep-dive notes the skill loads on demand.
- `agents/openai.yaml` — interface metadata (display name, icon, default prompt).
- `assets/` — SVG/PNG icons for the skill.

## How to onboard this into a new app project

Use the installer from the target repo:

```bash
# Pure-Swift Apple project — installs the "recommended" features set (default)
/path/to/AppBootstrapAI/install.sh . --platform apple

# Opt in to specialized features (Core Data, Foundation Models, etc.)
/path/to/AppBootstrapAI/install.sh . --platform apple --features all

# Cherry-pick categories
/path/to/AppBootstrapAI/install.sh . --platform apple --features core,testing,ui

# Legacy / Objective-C only
/path/to/AppBootstrapAI/install.sh . --platform apple --apple-language objc

# Mixed-language Apple project
/path/to/AppBootstrapAI/install.sh . --platform apple --apple-language both

# Android (default: recommended features)
/path/to/AppBootstrapAI/install.sh . --platform android

# Android + all features (including XML→Compose migration, R8/ProGuard)
/path/to/AppBootstrapAI/install.sh . --platform android --features all

# Cross-platform (one repo with both)
/path/to/AppBootstrapAI/install.sh . --platform both

# Preview catalog with category tags
/path/to/AppBootstrapAI/install.sh --list --platform apple --features all

# Full help — enumerates all 16 feature categories
/path/to/AppBootstrapAI/install.sh --help
```

The `--features` flag layers a feature-category filter on top of platform/language scoping. Default is `recommended`: a curated subset (`core`, `concurrency`, `ui`, `testing`, `docs`, `error-handling`, `packaging`, `logging`, `localization`, `linting`). `--features all` adds the specialized opt-ins (`persistence`, `ai`, `migration`, `shrinking`, `spatial`, `deployment`). Custom CSV lists give fine-grained control. The categories span both platforms — `--features testing` brings in both Apple's `swift-testing-pro` and Android's testing-strategy rule. `spatial` is visionOS-only and not in `recommended` — opt in via `--features recommended,spatial` for vision projects. `deployment` covers TestFlight + Play beta shipping flows; opt in via `--features recommended,deployment` when CI / release pipelines matter.

The installer copies skills (when Swift or Android is in scope) intersected with `--features`, platform-matching rules, settings, the platform-appropriate starter `CLAUDE.md`, and appends `.gitignore` entries. It never overwrites existing `CLAUDE.md` or `settings.json` — it prints what it skipped.

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
- "Use `android-gradle-architecture-pro` to review my multi-module Gradle setup."
- "Use `xml-to-compose-migration-pro` to migrate `SettingsFragment` to Compose."
- "Use `r8-shrink-pro` to audit my ProGuard rules before release."

Each skill produces a file-by-file findings report with before/after code fixes and a prioritized summary.

## Git workflow expectations

These apply to **every** AI session in this repo or in any repo that adopts this bundle. They're behavioral guardrails, not file-pattern rules, so they live in `CLAUDE.md` (always loaded) rather than `.claude/rules/`.

- **Never commit without an explicit instruction.** Edits to the working tree are fine; turning those into commits is a separate action that requires direct user instruction (e.g., *"commit this"*, *"make a commit"*, *"commit the changes"*). If a task naturally produces a commit and you're unsure whether the user wants one yet, **ask first.**
- **Never push to `origin` without an explicit instruction.** Pushing has user-visible side effects: CI runs, teammates see the changes, branches get published. Always wait for direct instruction (*"push"*, *"push to origin"*, *"open a PR"*).
- **Never amend an existing commit** unless the user explicitly asks (*"amend the last commit"*). Default to a new commit; amending rewrites history that may already be shared.
- **Never run destructive git commands without explicit confirmation:** `git push --force`, `git reset --hard`, `git checkout .`, `git restore .`, `git clean -f`, `git branch -D`, interactive `git rebase`. These can lose work irreversibly. If you think one is genuinely needed, name the command and ask before running it.
- **Never skip git hooks** (`--no-verify`, `--no-gpg-sign`) unless the user explicitly asks. Hooks usually catch real problems; bypassing them silently is exactly the kind of "surprising" behavior these rules exist to prevent.
- **Never force-push to `main`/`master`** even if the user asks. Warn them; offer a safer path (revert commit, new branch, etc.). The risk to teammates' local clones is too high.
- **When committing IS requested**, follow the standard project commit-message conventions (review recent `git log` first), stage specific files rather than `git add -A` (which can capture `.env` / credentials / temp files), and prefer creating a new commit over `--amend`.

The principle: **commits and pushes are user-driven actions**. Edits to the working tree are AI-driven; promoting them to history is the user's call.

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

### visionOS (`apple-visionos-best-practices.md`)

Specialized opt-in (`--features ...,spatial`). Not in `recommended` — vision teams pull it in explicitly. Covers the patterns that 2D-SwiftUI habits don't translate to:

- **Scene types** — `WindowGroup` / `Volume` (`.windowStyle(.volumetric)`) / `ImmersiveSpace` aren't interchangeable; only one ImmersiveSpace can open system-wide. Use `@Environment(\.openImmersiveSpace)` + `dismissImmersiveSpace`; always check `OpenImmersiveSpaceAction.Result` (user can cancel the consent dialog); tear down on `scenePhase` background.
- **Immersion styles** — default `.mixed`. Use `.progressive` for opt-in environmental separation; `.full` only when content IS the experience. Provide a visible exit; never trap.
- **Spatial gestures** — `SpatialTapGesture`, `RotateGesture3D`, `.targetedToEntity()`. Every interactive Entity needs a hover affordance (`HoverEffectComponent` + `InputTargetComponent` + `CollisionComponent`, or `.hoverEffect(.highlight)` on SwiftUI views).
- **Accessibility on an HMD is safety, not polish** — `@Environment(\.accessibilityReduceMotion)` is a vestibular guardrail; honor it for any motion (camera moves, particles, large transforms). Head-locked text causes vertigo; world-lock readable content. Never override system focus indicators.
- **RealityKit** — author in Reality Composer Pro, not code. Shallow Entity hierarchies. `.head` anchor only for HUD; `.plane` for world-locked default. Cache `findEntity(named:)` results; never re-walk in update closures.
- **Performance** — target 90fps. Frame drops cause nausea. Particles <1000 active; ~100k tri budget per Entity at 1–2m; prefer IBL over realtime lights; bake shadows.
- **USDZ pipeline** — `.usda` source, `.usdz` ship. Reality Composer Pro is the authoring tool. Load via `Entity(named:in: realityKitContentBundle)`; handle the throwing async path.

### TestFlight deployment (`apple-testflight-deployment.md`)

Specialized opt-in (`--features ...,deployment`). Operational rule — fires on `Fastfile`, `ExportOptions.plist`, `Info.plist`, `*.xcconfig`, CI YAML.

- **Versioning** — `CFBundleShortVersionString` (user-visible, semver-ish, reuse OK) vs `CFBundleVersion` (build number, **must monotonically increment**, never reuse). Compute build number from a monotonic CI source (`agvtool` / `PlistBuddy`); never hardcode in source.
- **App Store Connect API key (.p8)** is the modern auth — issuer + key ID + .p8 file, stored as base64 CI secrets. Don't use app-specific passwords for new automations (Apple is deprecating that path).
- **Canonical archive + export flow**: `xcodebuild archive` → `xcodebuild -exportArchive -exportOptionsPlist` → `xcrun altool --upload-app`. ExportOptions.plist must use `method: app-store-connect` (Xcode 15+), `signingStyle: manual` (for CI), explicit `provisioningProfiles` keyed by bundle ID.
- **Code signing**: `match` (fastlane) for shared certs across a team, or direct keychain import for solo teams. Never check `.p12` certs into source. Manual signing for CI; automatic only for local dev.
- **TestFlight tester groups**: Internal (≤100, no review, fast loop) vs External (≤10k, beta-review on each new `CFBundleShortVersionString`). Pick deliberately.
- **dSYM upload to Crashlytics/Sentry** runs as a post-archive CI step; `uploadSymbols: true` in ExportOptions.plist sends them to Apple separately for App Store Connect crash logs.
- **CI**: fastlane / GitHub Actions / Xcode Cloud. Same nine-step shape regardless of tool. Pin Xcode version, Ruby/Bundler/fastlane, dependency lockfiles.

### Play beta deployment (`android-play-beta-deployment.md`)

Specialized opt-in (`--features ...,deployment`). Operational rule — fires on `Fastfile`, `build.gradle{,.kts}`, `gradle.properties`, `keystore.properties`, `proguard-rules.pro`, CI YAML.

- **Versioning** — `versionCode` (integer, **monotonic, never reused**, Play rejects duplicates silently) vs `versionName` (string, user-visible). Compute `versionCode` from a CI env var; don't hardcode-and-commit (merge order becomes load-bearing).
- **Play App Signing — use it.** Splits keys: upload key (yours) and app signing key (Google's). Lose the upload key → reset via Play Console. Don't use Play App Signing → lose the app signing key → app is permanently un-updatable for existing users.
- **AAB, not APK.** New apps must upload `.aab` since August 2021. `./gradlew bundleRelease` (not `assembleRelease`). `bundletool` to convert AAB → device-specific APKs for local install testing.
- **Service account JSON for CI** — Play Console → API access → link a GCP service account, grant "Release manager" role on specific apps (not org-wide). Store JSON as a single CI secret.
- **Testing tracks**: internal (≤100, no review) → closed (review on first track upload) → open (public early-access listing). All version-locked — higher track blocks older builds in lower tracks.
- **Upload tools**: Triple-T `gradle-play-publisher` (Kotlin DSL, lowest-friction for Gradle projects) or fastlane `supply` (consistent CLI with the iOS side).
- **ProGuard / R8**: `isMinifyEnabled = true` on Release. `mapping.txt` auto-uploads to Play Console with the AAB; verify Crashlytics/Sentry plugins also upload (or release crashes show as `a.a.b()`).
- **Keystores never in source.** Decode from a base64 CI secret to disk; clean up on job exit.

### Apple localization (`apple-localization-best-practices.md`)

- String Catalogs (`.xcstrings`) are the modern source-of-truth (Xcode 15 / iOS 17+); legacy `.strings` / `.stringsdict` stays stable, new entries route through the catalog.
- All UI code reads through a **type-safe enum facade** (`Strings.Sections.title`, `Strings.Errors.portMin(value)`) so a typo is a compile error, not a runtime broken string. UI never calls `String(localized:)` / `NSLocalizedString` directly.
- `Text(_:)` / `.accessibilityLabel(_:)` accept `LocalizedStringResource` directly — use it.
- Plurals via String Catalog variations (Russian has 4 forms, Arabic has 6); never `count == 1 ? "item" : "items"`.
- Locale-aware formatters: `Text(value, format: .number)`, `Text(date, format: .dateTime.year().month().day())`, `.formatted(.currency(code:))`. Never `String(format: "%.2f", ...)` for user-visible output.
- RTL: use `.leading` / `.trailing`, never `.left` / `.right`. Test with the RTL pseudo-language scheme. `.flipsForRightToLeftLayoutDirection(true)` on directional images only.
- Every facade entry has a `comment:` for translators. Key naming carries context (`settings.save_button` over `save`).

### Android localization (`android-localization-best-practices.md`)

Scoped to `**/*.{kt,kts,xml}` (covers code and `res/values*/strings.xml`). Encodes:

- Every user-facing string in `res/values/strings.xml`; locale overrides in `values-<locale>/`, region overrides in `values-<lang>-r<REGION>/`.
- Compose: `stringResource(R.string.…)` / `pluralStringResource(R.plurals.…, count, count)`; non-Compose: `context.getString(...)` / `getQuantityString(...)`.
- **Always positional format args** (`%1$s`, `%2$d`) — never bare `%s`/`%d`. Translators reorder.
- `<plurals>` for any count-dependent string, even if English is `one`/`other`. Pass count *twice* to get it formatted in.
- Locale-aware `NumberFormat` / `java.time.DateTimeFormatter`; never `String.format("%.2f", ...)` or `SimpleDateFormat`.
- RTL: `<application android:supportsRtl="true">`; use `start`/`end` modifiers, never `left`/`right`. `android:autoMirrored="true"` on directional drawables.
- Comment blocks in `strings.xml` describe where strings appear and what each `%1$s` means.

### Apple linting (`apple-linting-strategy.md`)

In `recommended`. Fires on `.swift` + `.swiftlint.yml` / `.swiftformat` / `.swift-format`. Encodes:

- **Formatter vs linter — different jobs.** A formatter owns whitespace/layout deterministically; SwiftLint owns style + correctness smells. Pick **one** formatter (SwiftFormat *or* Apple's swift-format, never both) and disable SwiftLint's overlapping formatting rules so they don't fight.
- **`opt_in_rules` is where the value is** — SwiftLint ships ~200 rules with the best ones OFF by default. Enable `force_unwrapping` (top crash-class catch), `empty_count`, `first_where`, `explicit_init`, `unused_import`/`unused_declaration` (analyzer), etc.
- **Suppression hygiene** — `// swiftlint:disable:next <rule>` (single-line, auto-scoped) over the region `disable`/`enable` form; never blanket `disable all` (move to `excluded:` instead); every suppression gets a why-comment.
- **Analyzer rules** (`unused_import`, `unused_declaration`) need `swiftlint analyze` + a compiler log — CI only, not the build path.
- **Triage decision-order when a rule fires** — fix the code (default) > tune the rule's threshold globally > scope-suppress with a reason > disable project-wide (rare). Never invert it to clear one finding. Prioritize a backlog by tier: correctness (`force_unwrapping`) first → smells → style (autocorrect handles it).
- **Placement** — SPM build-tool plugin / Xcode Run Script / pre-commit / CI. CI uses `--strict` (warnings → errors); pin the SwiftLint version (rule sets change between releases).
- **Legacy adoption** — `excluded:` generated code, get to zero on default rules, add `opt_in_rules` a few at a time; no giant `disabled_rules` shortcut.

### Android linting (`android-linting-strategy.md`)

In `recommended`. Fires on `.kt`/`.kts` + `.editorconfig` / `detekt.yml` / `lint.xml` / build scripts. Three linters, **three non-overlapping jobs** — running one doesn't cover the others:

- **ktlint** — formatter + basic Kotlin style via `.editorconfig` (`ktlint_code_style`). `ktlintFormat` locally, `ktlintCheck` in CI. Disable `function-naming` so Compose `@Composable` PascalCase doesn't fight it.
- **detekt** — static analysis (complexity, bugs, smells). `buildUponDefaultConfig = true` and override thresholds; don't enable detekt's `formatting` ruleset alongside standalone ktlint (they duplicate). Type-resolution task (`detektMain`) in CI for the rules that need the classpath.
- **Android Lint** (`lintDebug`) — Android-platform checks ktlint/detekt can't see (resources, manifest, API misuse, a11y, security). `lint { abortOnError = true; warningsAsErrors = true; checkDependencies = true }`. Use `lintDebug`, not just `lintRelease`.
- **Baselines** (detekt + Android Lint) for legacy adoption — generate once, burn down; never regenerate to silence a failing CI (re-accepts new debt — the worst Android linting habit).
- **Suppression** — `@Suppress` / `@SuppressLint` scoped to the smallest element with a reason; never `@file:Suppress` as a shortcut.
- **Triage decision-order when a rule fires** — fix the code (default) > tune the rule's threshold/severity globally > scope-suppress with a reason > disable project-wide (rare). ktlint mostly skips triage (auto-fixable via `ktlintFormat`); triage is really for detekt + Android Lint. Prioritize by tier: correctness/security first → smells (baseline the rest) → formatting (ktlint owns it).
- **CI** — `./gradlew ktlintCheck detekt lintDebug`, all three as blocking checks; pin all three versions via the catalog.

### Apple documentation strategy (`apple-documentation-strategy.md`)

- Document every `public` / `open` symbol — summary line + `- Parameter` / `- Returns` / `- Throws` / complexity / concurrency / side effects / preconditions.
- Skip the signature-restating noise, generated code (Codable, `@Observable`), trivial accessors, and negative facts the type system already encodes.
- Use double-backticks for symbol links (` ``User.ID`` `); single backticks are *just* code formatting and don't link.
- Deprecate with mandatory `message:` and `renamed:` (when applicable) — no rotting deprecations; escalate to `obsoleted:` over releases.
- Use `// MARK: -` for source navigation; use DocC `## Topics` for the rendered API page.
- Prefer DocC Articles over multi-paragraph doc comments; samples must compile.

### Android documentation strategy (`android-documentation-strategy.md`)

- KDoc with `@param` / `@return` / `@throws` / `@property` / `@sample` / `@see`. Symbol references in `[brackets]`, not single backticks (Dokka doesn't link single backticks).
- For `@Composable`s: document state hoisting, semantics exposed to TalkBack, and skippable-vs-restartable status.
- For Hilt modules: explain *what* is bound and *why*, not just that the module exists.
- Suspend functions: document cancellation behavior and dispatcher requirements.
- Deprecate with mandatory `message =` and `replaceWith = ReplaceWith(...)`. Escalate `WARNING` → `ERROR` → `HIDDEN` over releases.
- Wire Dokka `externalDocumentationLink` to AndroidX/stdlib so symbols like `[Activity]` resolve.

### Project-level documentation (`project-documentation.md`)

Scoped to `README.md` / `CHANGELOG.md` / `CONTRIBUTING.md` / `docs/**/*.md`. Encodes:

- **README:** title + one-line description, badges (only if accurate), Quick Start (3–5 lines, real commands), Install, Usage (one realistic example), Configuration, Examples link, Contributing link, License link. No marketing copy before runnable code.
- **CHANGELOG:** [Keep a Changelog](https://keepachangelog.com) format — Added / Changed / Deprecated / Removed / Fixed / Security, ISO dates, PR/issue links per entry.
- **ADRs:** under `docs/adr/####-title.md`, immutable once accepted, supersede with new ADRs that link back.
- **Inline comments** explain *why*, not *what*. If you need a "what" comment, refactor first.
- **Link rot defenses:** pin versions in install commands, permalink to source by SHA (not `main`), avoid blog posts as canonical sources.

### Apple test strategy & coverage (`apple-testing-strategy.md`)

- Test pyramid: bulk unit tests, fewer integration, fewest UI (XCUITest, on schedule).
- Test the *behavior* through public API; skip private impl, third-party SDKs, generated code, DI wiring.
- Name tests by behavior (`loginRejectsExpiredToken`), not by method-under-test.
- Determinism is mandatory: inject clocks/UUIDs/randomness/network. No `Date()` / `UUID()` / `Thread.sleep` / live network in code under test.
- Default to Swift Testing for new tests; keep XCTest only for UI (`XCUITest`) and performance (`measure`).
- XCUITest: locate by `.accessibilityIdentifier`, never visible localized text.
- Coverage: track in CI (Slather / Codecov / `xcrun xccov`), set a *policy* gate (commonly 70–80%), exclude generated code, DI, model-only types, and `@main`. Coverage is a hint, not a goal — don't game it.

### Objective-C accessibility (`apple-objc-accessibility-best-practices.md`)

Scoped to `**/*.{h,m,mm}`. UIKit-side mirror of `apple-accessibility-best-practices.md`:

- Required properties: `accessibilityLabel` (localized via `NSLocalizedString`), `accessibilityHint` only when label is ambiguous, `accessibilityValue` for stateful controls, `accessibilityTraits` for semantic role.
- `accessibilityIdentifier` is for UI tests and **never localized**; `accessibilityLabel` is user-facing and **always localized**. Don't confuse them.
- Dynamic Type: `[UIFont preferredFontForTextStyle:]` + `adjustsFontForContentSizeCategory = YES`. Never `systemFontOfSize:` for user-visible text.
- Reduce Motion: `UIAccessibilityIsReduceMotionEnabled()` before animating; observe `UIAccessibilityReduceMotionStatusDidChangeNotification` for runtime toggles.
- VoiceOver announcements via `UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, ...)`; use sparingly.
- Modal overlays: `accessibilityViewIsModal = YES` so VoiceOver focus doesn't escape.
- Custom long-press / swipe actions: expose via `accessibilityCustomActions` so they're reachable from the VoiceOver rotor.

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
6. **Cross-tool rule sync** if your team uses Kiro / Gemini CLI / Cursor / Copilot alongside Claude Code. AppBootstrapAI stays Claude-native; point [`ruler`](https://github.com/intellectronica/ruler) or [`block/ai-rules`](https://github.com/block/ai-rules) at `.claude/` to fan the rules out to every other agent. Per-tool path conventions shift faster than this bundle ships — better to let a dedicated sync tool track them.

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

## Used by

AppBootstrapAI is the canonical source of AI rules and skills for downstream Kozinga projects:

- **KozBon** — multi-platform Bonjour service discovery app. Consumes the Apple rules + skills.
- **BasicSwiftUtilities** — foundational Swift 6 utilities package. Consumes the Apple rules + skills.

The bundled skills were originally authored by Paul Hudson and remain MIT-licensed with author attribution in each `SKILL.md`.

## License

MIT. See `LICENSE`. The bundled skills under `.claude/skills/` retain their original MIT license and author attribution in their frontmatter.
