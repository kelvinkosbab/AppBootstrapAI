# AppBootstrapAI

A drop-in bundle of **AI agent steering** — rules, skills (Claude), and MCP recipes — for bootstrapping new app projects. Covers Apple platforms (iOS, macOS, tvOS, watchOS, visionOS) and Android in one bundle, so single-platform and mixed-stack teams can share one source of truth. Works with **Claude Code, GitHub Copilot, Cursor, Gemini CLI, Codex CLI, and Amazon Kiro** out of the box (`./install.sh --agents <name>` writes the right files per agent).

One `install.sh` bootstraps modern review, testing, style, accessibility, and localization guidance into any new or existing app repo — and keeps it up to date with `--upgrade`. Day-one consistency without writing the rules yourself; day-N reproducibility without drifting from upstream.

**Claude Code is the default target, but the installer can write for other agents too.** Pass `--agents copilot,cursor,gemini,codex,kiro` (or `all`) and `install.sh` drops the right file shape per agent: `.github/copilot-instructions.md`, `.cursor/rules/*.mdc`, `GEMINI.md`, `AGENTS.md`, `.kiro/steering/*.md`. Skills stay Claude-only. For Cline / Goose / Roo / Windsurf etc., layer a sync tool — see [Using with non-Claude AI agents](#using-with-non-claude-ai-agents) below.

**Get started in one line:** `./install.sh setup` runs a guided flow that detects whether you're creating, adopting, or updating — and walks you through the rest. Prefer flags? See [Getting started](#getting-started).

## Contents

[What you get](#what-you-get) · [Getting started](#getting-started) · [Quick start](#quick-start) · [How it fires](#how-it-fires) · [Using AI to install](#using-ai-to-install) · [Upgrading](#upgrading-an-existing-install) · [Removing](#removing-the-install) · [Saving AI tokens](#saving-ai-tokens) · [Non-Claude agents](#using-with-non-claude-ai-agents) · [Repo layout](#repo-layout) · [Extending](#extending-for-your-project) · [Roadmap](#roadmap)

## What you get

The 30-second view. Expand any section below for the full rule-by-rule detail, or run `./install.sh --list --features all` for the always-current catalog.

| Area | What's inside |
|------|---------------|
| **Apple rules** | Swift 6 concurrency · SwiftUI MVVM · accessibility · testing · DocC · localization · SPM · linting · logging · Foundation Models · visionOS · TestFlight · Objective-C |
| **Android rules** | Kotlin/Compose/MVVM/Hilt · coroutines · accessibility · testing · KDoc · localization · Gradle · linting · logging · Play beta |
| **Skills (Claude)** | 10 Apple + 6 Android on-demand deep-review agents |
| **Agents** | One rule source → Claude Code, Copilot, Cursor, Gemini, Codex, Kiro |
| **MCP recipes** | XcodeBuildMCP · Xcode-native · android-mcp-server · Firebase · Sentry |
| **Lifecycle** | guided `setup` · `install` · `upgrade` (3-way diff — never clobbers your edits) · `uninstall` |

<details>
<summary><strong>Apple — 15 rules + 10 skills</strong> (click to expand)</summary>

- **`apple-swift6-strict-concurrency.md`** — Swift 6.4 strict concurrency (Xcode 27 toolchain; language mode `.v6`), enforced on every `.swift` file.
- **`apple-accessibility-best-practices.md`** — VoiceOver, Dynamic Type, Reduce Motion for SwiftUI (including streaming AI text), plus Bluetooth assistive tech: Full Keyboard Access (`.focusable()`, focus rings), Switch Control scan order, braille-display label discipline, focus management (`@AccessibilityFocusState`), modern announcements (`AccessibilityNotification`), audio/hearing (no sound-only cues, captions), WCAG AA color/contrast (both themes, Increase Contrast, Smart Invert), and App Store Accessibility Nutrition Label honesty.
- **`apple-foundation-models.md`** — Apple Foundation Models patterns: session ownership, two-level availability gating, streaming placeholder-then-mutate, `Task.isCancelled` discipline, protocol + mock + simulator testability.
- **`apple-swiftui-mvvm.md`** — SwiftUI MVVM conventions: when to extract a view model, `@State` vs `@Bindable` ownership, dependency plumbing, what stays on the View vs the view model, splitting large VMs across extension files.
- **`apple-objc-best-practices.md`** — Modern Objective-C for legacy / mixed-language codebases: ARC discipline, nullability, lightweight generics, `instancetype`, designated initializers, modern literals/blocks, Swift bridging-header conventions.
- **`apple-objc-accessibility-best-practices.md`** — UIKit accessibility in Objective-C: `accessibilityLabel` / `accessibilityHint` / `accessibilityTraits` discipline, `accessibilityIdentifier` vs `accessibilityLabel`, Dynamic Type via `preferredFontForTextStyle:`, `UIAccessibilityIsReduceMotionEnabled()`, VoiceOver announcements (`UIAccessibilityPostNotification`), modal-focus management (`accessibilityViewIsModal`), custom-action support, Full Keyboard Access + Switch Control via the focus system (`canBecomeFocused`, `accessibilityRespondsToUserInteraction`), braille-friendly labels, and announcement priority (`UIAccessibilitySpeechAttributeAnnouncementPriority`).
- **`apple-testing-strategy.md`** — what to test (and what not), Given/When/Then naming, determinism (inject clocks/UUIDs/network), Swift Testing vs XCTest split, XCUITest discipline, CI coverage gates with sensible exclusions.
- **`apple-documentation-strategy.md`** — what to document (and what not), DocC discipline (summary line, `- Parameter`/`- Returns`/`- Throws`, double-backtick symbol linking, `## Topics` organization), deprecation discipline with mandatory migration paths, when to write a DocC Article vs. a doc comment.
- **`apple-localization-best-practices.md`** — String Catalogs (`.xcstrings`) as the modern format, type-safe `Strings` enum facade pattern, `LocalizedStringResource` over `NSLocalizedString`, plurals, locale-aware `.formatted()` for numbers/dates/currency, RTL via leading/trailing modifiers, translator-context comments.
- **`apple-modular-architecture.md`** — the *architecture* stance behind the SPM conventions: a thin Xcode app target over a fat local Swift package split into many small modules (the KozBon / BasicSwiftUtilities shape). Why it wins (build parallelism, compile-enforced module boundaries, headless testing, reuse across widgets/extensions), the layered dependency graph (Core → domain → features → UI → `AppCore` umbrella the app links), the incremental migration playbook (scaffold, move leaf-first, thin the app target), and the `Bundle.module` / `.xcdatamodeld` caveats. Pairs with the `scripts/scaffold-spm-package.sh` scaffolder.
- **`apple-spm-package-conventions.md`** — `Package.swift` authoring: `swift-tools-version` discipline, mandatory `platforms:`, flat per-module folder layout (`{Module}/Sources/` + `{Module}/Tests/`, matching KozBon and BasicSwiftUtilities), `makeTargets()` helper for many similar modules with `hasTests` / `hasResources` / `plugins` toggles, resources (`.process` vs `.copy`), build plugins (SwiftLintPlugins, swift-docc-plugin), `Package.resolved` discipline (commit for apps, gitignore for libraries), local-path overrides for sibling-package development, modern features (`InternalImportsByDefault`, `.swiftLanguageMode(.v6)`, `public import`), dependency hygiene (`from:` vs `exact:`).
- **`apple-linting-strategy.md`** *(linting)* — SwiftLint as primary linter + a single formatter (SwiftFormat or Apple's swift-format, not both): `.swiftlint.yml` structure, the high-value `opt_in_rules` (`force_unwrapping`, `empty_count`, …), analyzer rules, scoped `// swiftlint:disable:next` hygiene, `--strict` in CI, build-phase vs SPM-plugin vs CI placement, incremental adoption on legacy code, version pinning, plus a triage decision-order.
- **`apple-logging-strategy.md`** *(logging)* — `Logger` / `OSLog` over `print` / `NSLog`, subsystem/category conventions (one `Logger` per category), privacy markers (`.public` / `.private` / `.private(mask: .hash)` — the part people get wrong), log levels (debug/info/notice/error/fault) and their persistence behavior, lazy `@autoclosure` interpolation, signposts for perf, what never to log (secrets/PII/bodies), retrieving logs via Console / `log` CLI / `OSLogStore`. Complements the `swift-logging-pro` skill.
- **`apple-visionos-best-practices.md`** *(spatial)* — visionOS: scene types (Window / Volume / ImmersiveSpace), immersion styles, spatial gestures + hover affordances, head-mounted-display accessibility (Reduce Motion as vestibular safety), RealityKit / ECS conventions, 90fps performance budgets, USDZ pipeline.
- **`apple-testflight-deployment.md`** *(deployment)* — shipping to TestFlight: `CFBundleVersion` monotonicity, App Store Connect API key (.p8) auth, `xcodebuild archive` → `-exportArchive` → `altool` flow, ExportOptions.plist gotchas, manual signing for CI, internal vs external tester groups, dSYM upload, ranked gotchas.
- **`swift-concurrency-pro` skill** — reviews async/await, actors, structured concurrency.
- **`swift-testing-pro` skill** — writes and migrates tests to Swift Testing.
- **`swiftui-pro` skill** — reviews SwiftUI for modern APIs and a11y compliance.
- **`coredata-swift6-pro` skill** — Core Data under Swift 6 strict concurrency, `viewContext`/`@MainActor`, SPM `.xcdatamodeld` caveats.
- **`swift-accessibility-pro` skill** — deep accessibility audit: the VoiceOver surface (labels/traits/merging/rotor/announcements), Bluetooth assistive input (Full Keyboard Access reachability, Switch Control scan order, braille label quality), visual accessibility (WCAG AA contrast in both themes, Dynamic Type at AX sizes, color-independence, Reduce Motion), and Nutrition-Label claim verification.
- **`swiftdata-pro` skill** — SwiftData review: core model/context rules, safe `#Predicate` usage, CloudKit constraints, iOS 18+ indexing, iOS 26+ class inheritance.
- **`swift-docc-pro` skill** — DocC comment review: parameter/return/throws tags, double-backtick symbol linking, Topics organization.
- **`swift-error-handling-pro` skill** — typed throws, Result vs throws, `LocalizedError`, Sendable errors, async propagation.
- **`swift-logging-pro` skill** — `os.Logger` review: subsystem/category conventions, privacy markers, log-level semantics.
- **`swift-package-pro` skill** — SPM library design: public API surface, `InternalImportsByDefault`, resources, versioning, dependency hygiene.

</details>

<details>
<summary><strong>Android — 12 rules + 6 skills</strong> (click to expand)</summary>

- **`android-project-rules.md`** — Kotlin, Jetpack Compose, MVVM, Hilt, StateFlow, Retrofit/Moshi, ktlint.
- **`android-coroutines-best-practices.md`** — structured concurrency, scope discipline (`viewModelScope`/`lifecycleScope`, no `GlobalScope`), dispatcher choice, `Flow`/`StateFlow`/`SharedFlow` exposure, cancellation safety.
- **`android-compose-best-practices.md`** — state hoisting, side effects (`LaunchedEffect`/`DisposableEffect`/`SideEffect`), `Modifier` ordering, recomposition stability (`@Stable`/`@Immutable`), lifecycle-aware `collectAsStateWithLifecycle()`, `LazyColumn` keys.
- **`android-accessibility-best-practices.md`** — TalkBack semantics, 48dp touch targets, dynamic text, WCAG AA contrast, reduce-motion, Bluetooth keyboard / switch-access focus discipline, braille displays (HID over Bluetooth, Android 15+), and the Android 16 `announceForAccessibility` deprecation (use live regions / `paneTitle` / `stateDescription`).
- **`android-testing-strategy.md`** — test pyramid, source-set discipline (`src/test` vs `src/androidTest`), `runTest` + `StandardTestDispatcher` patterns, Turbine for `Flow`, Compose UI tests via semantics (not visible text), Hilt test modules, MockK conventions, JaCoCo coverage gates with generated-code exclusions.
- **`android-documentation-strategy.md`** — KDoc syntax (`@param` / `@return` / `@throws` / `@property` / `@sample` / `@see`), Composable docs (state hoisting, semantics, skippable vs. restartable), Hilt module docs, suspend / cancellation behavior, deprecation with `ReplaceWith`, Dokka conventions and external links.
- **`android-localization-best-practices.md`** — `strings.xml` discipline, `stringResource` / `pluralStringResource` in Compose, positional format args (`%1$s` not `%s`), `<plurals>` with `getQuantityString`, locale-aware `NumberFormat` / `DateTimeFormatter`, RTL with `start`/`end` modifiers and `android:supportsRtl="true"`, translator-context comment blocks.
- **`android-gradle-conventions.md`** — Kotlin DSL only, version catalogs (`gradle/libs.versions.toml`) as single source of truth, AGP/Kotlin/Compose-compiler co-versioning, `jvmToolchain`, `api` vs `implementation`, multi-module graph patterns (`:app` + `:feature:*` + `:data:*` + `:core:*`), library publishing with `consumer-rules.pro`, KSP over kapt. **Now includes** an inline-strings → catalog migration walkthrough for legacy projects.
- **`android-linting-strategy.md`** *(linting)* — three linters, three jobs: ktlint (`.editorconfig`, formatting), detekt (`detekt.yml` tuning, `buildUponDefaultConfig`, type resolution, baselines), and Android Lint (`lint {}`, `lint.xml`, `warningsAsErrors`, baselines). `@Suppress` / `@SuppressLint` hygiene, CI placement (`ktlintCheck detekt lintDebug`), version pinning, plus a triage decision-order.
- **`android-logging-strategy.md`** *(logging)* — Timber over `android.util.Log` (plant a tree in `Application.onCreate`), log levels (V/D/I/W/E/WTF) and passing the `Throwable`, **stripping debug logs from release** (DebugTree-in-debug-only + R8 `assumenosideeffects`), no PII/secrets, crash-reporter integration (Crashlytics/Sentry breadcrumbs + non-fatals via a `CrashReportingTree`), Logcat hygiene.
- **`android-ai-best-practices.md`** *(ai)* — in-app AI models on Android, the counterpart to the Apple Foundation Models rule: on-device Gemini Nano via ML Kit GenAI / AICore vs cloud Gemini via Firebase AI Logic, **never ship a raw model API key** (App Check / backend proxy), two-level availability gating (feature download + user preference), streaming into Compose with placeholder-then-mutate, structural cancellation, interface + fake testability, consent + Data-safety implications.
- **`android-play-beta-deployment.md`** *(deployment)* — shipping to Play beta tracks: `versionCode` monotonicity, Play App Signing (upload key vs app signing key), AAB-not-APK, service-account JSON for CI, internal/closed/open tracks, Triple-T / fastlane upload, `mapping.txt` upload, ranked gotchas.
- **`android-accessibility-pro` skill** — deep accessibility audit: the TalkBack semantics tree (descriptions/roles/merging/state/custom actions/live regions incl. the Android 16 announcement migration), Bluetooth input (keyboard/Switch Access/braille), visual accessibility (contrast in both themes, sp scaling at 200%, 48dp targets, reduce motion).
- **`android-compose-pro` skill** — deep Compose review: recomposition stability + skippability (incl. strong-skipping-mode awareness), side-effect audit (`LaunchedEffect` keys, `rememberUpdatedState`, `DisposableEffect` teardown), lazy-list performance (keys, `contentType`, `derivedStateOf` for scroll), state modeling and hoisting.
- **`android-coroutines-pro` skill** — deep coroutines/Flow review: scope-to-lifecycle mapping, cooperative cancellation (`CancellationException` discipline, `runCatching` traps), `launch` vs `async` exception propagation, supervisor boundaries, `stateIn`/`shareIn` configuration, `callbackFlow` teardown, coroutine testing (virtual time, Turbine).
- **`android-gradle-architecture-pro` skill** — reviews multi-module Android builds against the **Now in Android** convention-plugin pattern: `build-logic/convention/` factoring, version-catalog depth, AGP co-versioning, KSP-over-kapt migration.
- **`xml-to-compose-migration-pro` skill** — reviews and assists XML/Fragment → Compose migration: incremental interop via `ComposeView` / `AndroidView`, layout translation (LinearLayout/ConstraintLayout/FrameLayout → Modifier), RecyclerView → `LazyColumn` with stable keys, Fragment → Composable, Navigation Component → Navigation-Compose, ViewModel bridging, themes/styles → `MaterialTheme`.
- **`r8-shrink-pro` skill** — reviews R8 / ProGuard configuration: `-keep` rule discipline, `consumer-rules.pro` contract for libraries, common reflection-library rules (Moshi, Room, Retrofit, Hilt, Glide, kotlinx-serialization), mapping-file workflow, debugging release-build crashes.

</details>

<details>
<summary><strong>Cross-platform — 2 rules</strong> (click to expand)</summary>

- **`concise-comments-and-commits.md`** *(core)* — fires on all Swift/Kotlin/ObjC source: in-code comments default to *none* (write only what code can't express — why, traps, ticket refs; never narration, diff commentary, or commented-out code), and commit messages stay short (imperative ≤72-char subject; body only when the why isn't in the diff — never file-by-file inventories or process reports). Aimed squarely at AI-assistant verbosity.
- **`project-documentation.md`** — README structure, [Keep a Changelog](https://keepachangelog.com) format, `CONTRIBUTING.md` essentials, ADR conventions (`docs/adr/####-title.md`, immutable once accepted), inline-comment philosophy (*why* not *what*), and link-rot defenses (pinned versions, permalinked source). Scoped to `README.md` / `CHANGELOG.md` / `CONTRIBUTING.md` / `docs/**/*.md`.

</details>

<details>
<summary><strong>Baseline &amp; bundle files</strong> — settings, .gitignore, the full <code>install.sh</code> flag reference, templates (click to expand)</summary>

- **`settings.json`** — safe defaults for `xcodebuild`, `swift`, `swiftlint`, `./gradlew`, `gradle`, `ktlint`, `adb`, `git`, `gh`, plus Apple/Android docs domains for `WebFetch`.
- **`.gitignore`** — recommended entries for Xcode, SPM, CocoaPods, Carthage, fastlane, plus Gradle/Android Studio/Kotlin.
- **`install.sh`** — one-command bootstrap into any target repo.
  - **Commands** (verb form): `install [TARGET]` (default — verb optional), `recommend [TARGET]` (analyze a dir → suggested command, `--json` for agents), `upgrade TARGET`, `uninstall TARGET`, `list`, `list-mcps`, `setup` (guided), `help`. Each has a legacy `--flag` alias (`--upgrade`, `--uninstall`, `--list`, `--list-mcps`, `-i`/`--interactive`, `-h`/`--help`) — verbs and flags are interchangeable, so existing scripts keep working. A directory whose name collides with a verb can be targeted via an explicit path (`./upgrade`) or the `--flag` form.
  Flags:
  - `-i` / `--interactive` — guided, prompt-driven setup. Detects create vs. adopt vs. update and walks through platform / Apple-language / features / agents / MCP recipes with defaults. Works at a TTY or from piped stdin (Enter accepts each default); prints a plan and confirms before writing. See [Getting started](#getting-started).
  - `--new` — create the target directory (and parents) and `git init` a fresh repo before installing, for green-field projects. Light scaffolding only — does not generate an Xcode/Gradle project. Install-only (rejected with `--upgrade`/`--uninstall`).
  - `--force` — allow a plain `install` over a directory that's already a managed AppBootstrapAI install. Without it, re-installing over a managed repo is refused with guidance to use `--upgrade` (which preserves the manifest baseline). Install-only.
  - `--platform apple|android|both` — optional; if omitted, the installer auto-detects from the target dir (`Package.swift` / `*.xcodeproj` → apple; `build.gradle*` / `gradlew` → android; both present → both; neither → falls back to `both`). Detection result + matched signals print in the install header. Explicit `--platform` always wins.
  - `--apple-language swift|objc|both` (legacy ObjC projects skip Swift-only rules)
  - `--apple-platforms ios,macos,tvos,watchos,visionos|all` — which Apple sub-platforms you target. Default `ios,macos,tvos,watchos` (every platform **except** visionOS — the lean default for typical app projects). Only meaningful when Apple is in scope. Today the one platform-specific rule is visionOS, so this stays in sync with the `spatial` feature: naming `visionos` installs the visionOS rule, omitting it keeps it out. Recorded in the manifest; a forward-looking framework for future platform-specific rules.
  - `--android-platforms phone,tablet,wear,tv,auto|all` — which Android form factors you target. Default `phone,tablet`. Only meaningful when Android is in scope. **No Android rule is form-factor-specific today**, so unlike `--apple-platforms` this does **not** change what installs — it's recorded in the manifest and is a forward-looking framework (a Wear OS / Android TV / Auto rule would gate by these tokens).
  - `--features all|recommended|<csv>` — **default `recommended`** is a curated subset for most apps (now includes `linting`); `all` adds specialized opt-ins (`persistence`, `ai`, `migration`, `shrinking`, `spatial`, `deployment`); custom CSVs like `core,testing,docs` give fine-grained control
  - `--list` previews the catalog with one-line descriptions + category tags
  - `--list --json` emits the same catalog as machine-readable JSON (used by the MCP server)
  - `--list-mcps` lists available MCP-server recipes (name, platform, description, homepage)
  - `--with-mcps <csv>` writes one `mcpServers.<name>` entry per recipe into `.claude/settings.local.json`. Existing entries are never overwritten. Setup notes (auth, env vars) print after install. See [`mcp-recipes/`](mcp-recipes/) for the available recipes.
  - `--agents <csv>` picks which AI agents to install for. Default `claude`; additive options: `copilot` (writes `.github/copilot-instructions.md`), `cursor` (writes `.cursor/rules/*.mdc`), `gemini` (writes `GEMINI.md`), `codex` (writes `AGENTS.md`), `kiro` (writes `.kiro/steering/*.md`), or `all`. Same rule content, per-agent file shape. Skills are Claude-only.
  - `--dry-run` shows what an install would do without writing any files
  - `--upgrade` prints a per-file plan of what would change if you re-installed today — classified as up-to-date / safe update / local-edits / conflict / orphan / addition / out-of-scope / rename. Add `--apply` to execute the plan; `--force-conflicts` to overwrite locally-edited files where the bundle also changed; `--prune` to delete orphans + out-of-scope files; `--migrate-manifest` to bring a v1 manifest forward. The header prints a GitHub compare URL when commits differ. See [Upgrading an existing install](#upgrading-an-existing-install).
  - `--uninstall` reverses install: deletes every tracked file whose current hash matches what was installed (locally-edited files kept unless `--force-conflicts`; `CLAUDE.md` / `settings.json` kept unless `--purge`). MCP entries are removed if unchanged, unless `--keep-mcps`. Strips the `.gitignore` block and the manifest itself. See [Removing the install](#removing-the-install).
  - `--help` documents every flag and enumerates all 16 categories
  - Every install writes a manifest at `.claude/.appbootstrap-manifest.json` (schema v2 — records per-file SHA-256 hashes so `--upgrade` can diff 3-way: installed vs. current disk vs. bundle)
- **Three starter `CLAUDE.md` templates** — `templates/CLAUDE.template.apple.md`, `templates/CLAUDE.template.android.md`, `templates/CLAUDE.template.md` (cross-platform). The installer picks the right one based on `--platform`.
- **`templates/Package.template.swift`** — starter Swift Package Manager manifest with a `makeTargets(name:dependencies:hasTests:hasResources:testDependencies:testResources:)` helper. Adding a new module is a two-line change: one line in `products:` and one `+ makeTargets(...)` block in `targets:`. Copy it into a new SPM package as `Package.swift` and fill in the placeholders.
- **`scripts/scaffold-spm-package.sh`** — generates a KozBon-style local package (`<App>Packages/`) so an existing app can move its logic out of the `.xcodeproj` and into modules. Emits a `makeTargets()`-based `Package.swift` from `--modules Core,…,AppCore` plus a compiling source + passing test placeholder per module; a module named `AppCore` becomes the umbrella the app links. Non-destructive (never overwrites; `--dry-run` / `--force`). Pairs with the `apple-modular-architecture.md` rule.

</details>

<details>
<summary><strong>Recommended companion MCP tooling</strong> (optional — click to expand)</summary>

#### MCP servers for the Apple side

- **Xcode 27 native MCP + agent platform** *(WWDC 2026)* — Apple massively expanded the in-Xcode agent story (building on the Xcode 26.3 `mcpbridge` foundation). The native **Xcode MCP server** now adds debug tools (run state, debugger console, schemes, destinations, build settings, entitlements, `Info.plist`), a **Preview Snapshot** tool, simulator control (boot/install/launch, synthesize touches, screenshots), and access to project insights (crashes, hangs, energy). **LLDB ships its own `lldb-mcp`** server ([docs](https://lldb.llvm.org/use/mcp.html)). Most relevant to *this* bundle: Xcode 27 gains **agent plug-ins** — bundling **skills, MCP servers, ACP (Agent Client Protocol) configurations, and slash commands** — plus Apple-built specialists (localization, accessibility, UIKit resizing) and a security layer governing agent filesystem access. First-party, no separate install. See Apple's [Giving agentic coding tools access to Xcode](https://developer.apple.com/documentation/xcode/giving-agentic-coding-tools-access-to-xcode).
- **[XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP)** — community MCP server that lets any agent drive Xcode: build schemes, run simulators, capture logs. Still useful alongside the native server — it leans into richer test/simulator tooling and works from agents outside Xcode. Especially valuable for legacy / mixed-language Apple codebases and for CI-style automation.

#### MCP servers for the Android side

- **[Android Studio's built-in MCP support](https://developer.android.com/studio/gemini/add-mcp-server)** — Google ships first-party MCP integration in Android Studio. Hook any MCP server (including this repo's, see below) directly into Studio's agent.
- **[`android-mcp-server`](https://github.com/minhalvp/android-mcp-server)** — community MCP server that gives agents control over Android devices and emulators via ADB. The Android-side parallel to XcodeBuildMCP's simulator work.

#### Cross-platform / shared

- **[Firebase MCP](https://github.com/firebase/firebase-tools/tree/main/src/mcp)** — **first-party from Google.** Lives in `firebase-tools`. Covers Crashlytics, Remote Config, App Hosting, Realtime DB, and Cloud Functions logs. Crashlytics surface is marked experimental.
- **[Sentry MCP](https://docs.sentry.io/product/sentry-mcp/)** — **first-party, hosted by Sentry** at `mcp.sentry.dev/mcp`. Streamable HTTP with OAuth — zero install for sentry.io users. Exposes issues, errors, projects, and Seer analysis.

**See also** (specialized; add when the use case fits):

- **[`ios-simulator-mcp`](https://github.com/joshuayoes/ios-simulator-mcp)** — npm-installable, iOS-Simulator-only (screenshots, UI hierarchy, tap/swipe). Lighter than XcodeBuildMCP if Simulator control is all you need.
- **[Mobile MCP (`mobile-next/mobile-mcp`)](https://mcpservers.org/servers/mobile-next/mobile-mcp)** — cross-platform iOS + Android automation via accessibility snapshots + coordinate taps. QA-style workflows that span both platforms.
- **[`kotlin-mcp-server`](https://github.com/normaltusker/kotlin-mcp-server)** — heavier-touch Android dev workflow MCP: Gradle, ktlint, Lint, Room / Retrofit / Compose scaffolding via AI prompts.
- **[Figma MCP](https://help.figma.com/hc/en-us/articles/32132100833559-Guide-to-the-Figma-MCP-server)** — first-party Figma server for design → code workflow. Mobile-relevant when your design source is Figma; not mobile-specific.
- **App Store Connect** and **Google Play Console** MCPs exist but the ecosystem is still consolidating around a winner — multiple competing community implementations. Worth watching but no recommendation yet.
- **Linear / Jira / Atlassian** MCPs (Atlassian's is GA Feb 2026, Linear's is first-party) are excellent but cover generic project-management concerns, not mobile-app-specific work — they belong in your generic MCP setup, not this list.

#### Cross-tool rule sync

- **Multi-agent support** — pass `--agents copilot,cursor,gemini,codex,kiro` to `install.sh` and the bundle writes the right file shape for each agent (in addition to or instead of Claude). For agents not in that built-in set (Cline, Goose, Roo, Windsurf, etc.), point a sync tool at `.claude/`. See [Using with non-Claude AI agents](#using-with-non-claude-ai-agents).

</details>

## Getting started

The installer takes a **command verb** — `install` (the default, so it can be
omitted), `upgrade`, `uninstall`, `list`, `list-mcps`, or `setup`. Three ways in,
depending on where you are. Not sure which? Run **`setup`** and it figures it out:

```bash
# Guided, prompt-driven — detects create vs. adopt vs. update and walks you
# through platform, features, agents, and MCP recipes with sensible defaults.
/path/to/AppBootstrapAI/install.sh setup
```

> **Verbs and flags are interchangeable.** Every verb has a legacy flag alias —
> `upgrade` == `--upgrade`, `uninstall` == `--uninstall`, `list` == `--list`,
> `setup` == `-i` / `--interactive`. Existing scripts that use the flag form keep
> working unchanged.

### 1. New project (green-field)

Create the directory, `git init` it, and install the bundle in one step:

```bash
/path/to/AppBootstrapAI/install.sh install ~/Projects/MyNewApp --new --platform apple
```

`--new` makes the target dir (and parents) and initializes a fresh git repo,
then installs. It's light scaffolding — it does **not** generate an Xcode or
Gradle project; create that with Xcode / Android Studio, then commit.

### 2. Existing project (adopt)

Point the installer at your repo root. Platform auto-detects from the files
already there (`install` is the default verb, so you can omit it):

```bash
cd /path/to/your/app
/path/to/AppBootstrapAI/install.sh .
```

Nothing you've authored gets overwritten — an existing `CLAUDE.md`,
`settings.json`, or agent file is left alone and the installer prints what it
skipped so you can merge by hand.

### 3. Update an existing install (stay current with upstream)

Once a repo is managed (it has a `.claude/.appbootstrap-manifest.json`), use
`upgrade` — never a plain re-install:

```bash
/path/to/AppBootstrapAI/install.sh upgrade .           # plan-only preview
/path/to/AppBootstrapAI/install.sh upgrade . --apply   # execute the plan
```

`upgrade` runs a 3-way diff (what was installed vs. your current files vs. the
latest bundle) so your local edits are preserved. A plain `install` over a
managed repo is **refused** with guidance to use `upgrade` — that guard stops
a re-install from silently resetting the manifest baseline. If you genuinely
want to re-install over a managed target, pass `--force`.

## Quick start

The full flag reference. Examples below use the bare/`install` form; prefix any
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
/path/to/AppBootstrapAI/install.sh . --agents copilot   # → .github/copilot-instructions.md
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

**The default `--features recommended` set** covers what most apps need on day one: `core` (project docs) + `concurrency` + `ui` + `testing` + `docs` (code documentation) + `error-handling` + `packaging` + `logging` + `localization` + `linting` (SwiftLint+formatter / ktlint+detekt+Android Lint). Specialized opt-ins not in `recommended`: `persistence` (Core Data / SwiftData), `ai` (Apple Foundation Models + Android Gemini Nano / Firebase AI Logic), `migration` (XML → Compose), `shrinking` (R8/ProGuard), `spatial` (visionOS scene types, immersion styles, spatial gestures, RealityKit conventions), `deployment` (TestFlight + Play beta tracks — versioning, signing, CI patterns, common gotchas).

**The default `--agents claude` set** writes the native Claude Code layout. Pass `--agents copilot|cursor|gemini|codex|kiro|all` (additive CSV) and the installer also drops the matching file shape for those agents (one concat file for Copilot/Gemini/Codex; per-rule files for Cursor `.mdc` and Kiro `.kiro/steering/*.md`). See [Using with non-Claude AI agents](#using-with-non-claude-ai-agents) for the per-agent table.

The installer:

- Copies skills matching the platform/language/features intersection (Apple skills when `--agents claude` and Apple/Swift in scope; Android skills similarly). Skills are Claude-only — non-Claude agents get rules only.
- Copies platform-matching `.claude/rules/` filtered by `--features` (when `--agents claude` is selected).
- Generates per-agent files for each agent in `--agents` (e.g., `.github/copilot-instructions.md`, `.cursor/rules/*.mdc`, `GEMINI.md`, `AGENTS.md`).
- Copies `.claude/settings.json` (only if `--agents claude` and one doesn't already exist).
- Renders the **platform-appropriate** `CLAUDE.template.*.md` into `CLAUDE.md` (only if `--agents claude` and missing): `apple` → `CLAUDE.template.apple.md`, `android` → `CLAUDE.template.android.md`, `both` → `CLAUDE.template.md`.
- Appends platform-specific entries to `.gitignore`, deduped by marker. Adds `.cursor/state*` / `.cursor/.cache/` entries when `--agents cursor` is selected.
- Writes `.claude/.appbootstrap-manifest.json` recording every installed file (with per-file SHA-256) plus the full selection (`--platform`, `--apple-language`, `--features`, `--agents`).

It never overwrites an existing `CLAUDE.md`, `settings.json`, or any agent file (`copilot-instructions.md`, `GEMINI.md`, etc.) — it prints what it skipped so you can merge.

`--dry-run` skips every write but still prints what would happen, so you can preview before committing to an upgrade.

After install, edit the new `CLAUDE.md` (or your agent's equivalent) and fill in the `<PLACEHOLDER>` sections. Keep the bundled rules and skills as-is unless you need to extend them.

> **Using a different agent?** `install.sh --agents copilot|cursor|gemini|codex|kiro|all` writes the right files natively. See [Using with non-Claude AI agents](#using-with-non-claude-ai-agents) for the per-agent file layout. For agents not in that built-in set, point a sync tool like [`ruler`](https://github.com/intellectronica/ruler) at `.claude/`.

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

`install.sh` is a shell command — every coding agent can run it. Agents operating this package should read [`AGENTS.md`](AGENTS.md) — a terse, machine-first guide to the create / adopt / update workflow. If you'd rather *ask* the agent to bootstrap your repo than run the script by hand, four things make that work well:

1. **Let the package do the analysis: `./install.sh recommend <dir>`.** This is the fastest path for an agent. Point it at any directory and it introspects the repo — managed-state, platform, Apple-language, and framework usage (`import FoundationModels` → `ai`, Core Data / SwiftData → `persistence`, Room → `persistence`, R8/ProGuard → `shrinking`, fastlane/CI → `deployment`, …) — then prints the **exact** create / adopt / upgrade command to run, with the reasoning behind each choice. Add `--json` for a machine-readable object (with a ready-to-exec `command` array) instead of prose. One call replaces the agent grepping the tree by hand.

   ```bash
   # Human-readable
   /path/to/AppBootstrapAI/install.sh recommend ~/Projects/MyApp
   # Machine-readable (the agent parses `command` / `preview_command`)
   /path/to/AppBootstrapAI/install.sh recommend ~/Projects/MyApp --json
   ```

   The recommended flow for an agent is **`recommend` → run the suggested `--dry-run` preview → run the real command**.
2. **Hand the agent this repo's URL and your project description.** Most agents need just enough context to pick the right flags. A prompt like *"Bootstrap this iOS+macOS app with AppBootstrapAI — Swift only, include the AI/Foundation Models category"* tells Claude / Cursor / Gemini / Kiro / Copilot what they need to know.
3. **The agent can introspect the catalog before installing.** `./install.sh --list --features all` prints every rule and skill with its category and one-line description. Agents that read the output can recommend the right `--features` list for your project.
4. **For agents that speak MCP** (Claude Code, Cursor, others with MCP client support), this repo ships an [MCP server](mcp-server/README.md) that exposes the installer as nine structured tools: **`recommend_setup`** (call first — analyze a dir → suggested command), `list_categories`, `list_rules`, `list_skills`, `preview_install`, `install`, `preview_upgrade`, `preview_uninstall`, and `uninstall`. Wire it into your agent's MCP config and the agent runs the installer through a typed API rather than parsing shell output. See [`mcp-server/`](mcp-server/) for setup.

**Recommended prompts** (copy-paste-friendly for the agent of your choice):

| Goal | Prompt |
|------|--------|
| Bootstrap a new Apple SwiftUI app with the recommended set | *"Run `/path/to/AppBootstrapAI/install.sh . --platform apple` in this directory, then walk me through what landed."* |
| Bootstrap an Android Compose app with everything | *"Run `/path/to/AppBootstrapAI/install.sh . --platform android --features all` and summarize the new files."* |
| Pick categories interactively | *"Show me `./install.sh --list --features all`, then ask me which categories to install."* |
| Cross-platform monorepo with specific features | *"Bootstrap this repo for both Apple (Swift) and Android. Include `core`, `testing`, `docs`, `concurrency`, `ui`, and `localization`."* |
| Mixed-language Apple project (Swift + ObjC) | *"Run `./install.sh . --platform apple --apple-language both --features all`."* |

Agents that run in a terminal context (Claude Code, Cursor's agent mode, Gemini CLI, Kiro, Codex CLI) execute the shell command directly. Agents without shell access (Copilot Chat, web Claude.ai) can produce the command for you to run.

## Building with AI agents (after install)

Installing the bundle is step one; the payoff is how your agent behaves while you build. A few habits get the most out of it:

1. **Rules steer the agent's output — but most are review-time conventions, not compiler-enforced.** The agent writes to the rules automatically, yet several say so outright (*"enforced by review, not the compiler"*). Review what lands, and when the agent slips, *name the rule*: *"this violates `apple-swiftui-mvvm.md` — fix the ownership."* Citing the file points the agent at the exact text and it self-corrects.
2. **Invoke the deep-review skills explicitly — don't wait for auto-fire.** Skills (`.claude/skills/`) are on-demand review agents that load only when asked. After the agent writes a feature, request the matching review: *"Use `swiftui-pro` to review `SettingsView.swift`"*, *"Use `android-compose-pro` to check `FeedScreen.kt` for recomposition bugs."* Each produces a file-by-file findings report with before/after fixes.
3. **Skills are Claude-only; other agents get the rules as steering.** Cursor, Copilot, Gemini, Codex, and Kiro receive the rules in their native format (see [Using with non-Claude AI agents](#using-with-non-claude-ai-agents)) but not the deep-review skills. With those agents, ask for a manual pass instead: *"Review this against `.claude/rules/android-coroutines-best-practices.md`."*
4. **Keep sessions scoped — it's correctness *and* token economy.** Rules are glob-scoped, so only the ones matching the files you're touching load into context. A focused session (one subsystem, its relevant rules) gives sharper steering and a smaller bill than a sprawling one. More in [Saving AI tokens](#saving-ai-tokens).
5. **Put project-specifics in `CLAUDE.md`.** The agent reads it first. The module graph, build commands, and gotchas you record there compound with the bundle's rules — and a pattern you catch yourself correcting twice belongs in a new `.claude/rules/<name>.md`.
6. **Stay current.** New platform APIs land in the rules each Xcode / AGP cycle. Run `upgrade` periodically so the steering reflects them — see [Upgrading an existing install](#upgrading-an-existing-install).

## Upgrading an existing install

Once a repo has run `install.sh`, the bundle keeps evolving — new rules ship, existing rules get tightened, skills gain references. The `--upgrade` flow lets you see what would change and apply it surgically, without ever touching files you've customized.

```bash
# 1. Plan — read-only preview. Inherits --platform / --apple-language / --features from the manifest.
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade

# 2. Apply — execute the safe rows. Conflicts default to SKIP; orphans stay.
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade --apply

# 3. Apply + opt into a new feature category (e.g., adopt Foundation Models support post-iOS-26).
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade --features recommended,ai --apply

# 4. Preview apply without writing — combines --apply with --dry-run.
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade --apply --dry-run

# 5. Aggressive: overwrite locally-edited files where the bundle also changed (loses local edits).
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade --apply --force-conflicts

# 6. Aggressive: delete files retired upstream or no longer in --features.
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade --apply --prune
```

The plan classifies every tracked file:

- **Up to date** — installed hash matches the bundle. No action.
- **Safe to update** — bundle has new content; you haven't touched the file locally. `--apply` overwrites.
- **Locally edited** — you modified the file after install; bundle unchanged. The upgrade always leaves these alone.
- **Conflict** — both local edits and upstream changes since install. Default is skip-with-warning; `--force-conflicts` overwrites.
- **Out of scope** — file was installed under one `--features` set but isn't part of the current selection. Manifest tracks it; `--prune` removes it.
- **Retired upstream** — bundle no longer ships this file. Listed but not auto-deleted; `--prune` removes it.
- **Would add** — new files in the bundle that fit your current `--features` and aren't in the manifest yet. `--apply` writes them.

The diff is **3-way per file**: installed hash (what we wrote at install), current disk hash (what's there now), and bundle hash (what the bundle ships today). That's how the plan can tell *"you've edited this"* apart from *"someone re-ran an installer."*

### Migrating from older manifests

Installs from before manifest schema v2 don't have content hashes recorded, so the diff has no baseline. The migration is a single command — no files are touched, only the manifest is rewritten:

```bash
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade --apply --migrate-manifest
```

After migration, future `--upgrade` runs can do real 3-way diffs. Note: v1 `mcps_requested` is not carried over; re-add MCPs via `--with-mcps` if needed.

### MCP entries get the same 3-way diff

MCP recipes installed via `--with-mcps` are tracked in the manifest with their `config_sha256`. `--upgrade` runs the same per-entry classification on `.claude/settings.local.json`:

- **Up to date** — recipe config matches what's in `settings.local.json` and the manifest.
- **Safe to update** — recipe shipped a new config; you haven't touched the entry. `--apply` overwrites `mcpServers.<name>`.
- **Locally edited** — you customized the entry (changed args, added env vars). Always left alone.
- **Conflict** — both you AND the recipe diverged from the original. Default skip; `--force-conflicts` overwrites.
- **Orphan** — recipe no longer ships in the bundle, OR the entry vanished from `settings.local.json`. `--prune` drops the manifest record (and removes the `mcpServers.<name>` entry if it still exists).

The hash is computed over the recipe's `config` object with stable sort + compact separators, so reformatting `mcp-recipes/<name>.json` doesn't drift the hash.

### Renames

When the bundle renames a rule or skill upstream, the rename is tracked in [`RENAMES.md`](RENAMES.md) at the bundle root. The upgrade plan folds the migration into a single rename row instead of "deleted X, added Y." Two forms:

- **Rule renames** (file-level): `apple-old.md → apple-new.md`. Resolves to `.claude/rules/<old>.md` → `.claude/rules/<new>.md`.
- **Skill renames** (directory-level): `swift-old-pro → swift-new-pro`. Resolves to a path-prefix rewrite of every file under the old skill dir.

Renames classify as **safe** (current matches installed or bundle — moving the file loses nothing) or **conflict** (you have uncommitted edits at the old path, OR the new path already exists from a user-authored file). Default skip on conflict; `--force-conflicts` applies anyway.

### Where the bundle changed: the GitHub compare URL

When the upgrade plan detects that the bundle's current `git rev-parse HEAD` differs from what the manifest recorded at install time, and the bundle's `origin` remote is a GitHub URL, the header prints a compare link:

```
  installed bundle commit: 6a1afb1461fb
  current bundle commit:   30ee587195be
  changes between them:    https://github.com/kelvinkosbab/AppBootstrapAI/compare/6a1afb14...30ee5871
```

Click through to see exactly what shipped between your install and now. Falls back gracefully when the bundle isn't a git checkout, has no GitHub remote, or both commits resolve to "unknown".

### Things the upgrade flow won't do

- **`CLAUDE.md`** is never auto-touched. The plan surfaces "template advanced upstream" when relevant; the diff is for you to apply by hand. `CLAUDE.md` fills with project-specific content fast, so auto-merge is dangerous.
- **`.claude/settings.json`** gets the same treatment for the same reason — you probably added permissions, tweaked allowlists. The plan informs; you merge.
- **Non-`mcpServers` keys in `settings.local.json`** are preserved across upgrade-apply. Only `mcpServers.<name>` entries listed in the manifest's `mcps_installed` get touched.
- **MCP additions** — `--upgrade` doesn't auto-add new MCP recipes. Adding an MCP is always explicit via `--with-mcps <name>`.

## Removing the install

```bash
# Default — delete every tracked file that hasn't been edited; keep CLAUDE.md / settings.json.
/path/to/AppBootstrapAI/install.sh /your/repo --uninstall

# Preview without writing
/path/to/AppBootstrapAI/install.sh /your/repo --uninstall --dry-run

# Aggressive: also delete locally-edited tracked files
/path/to/AppBootstrapAI/install.sh /your/repo --uninstall --force-conflicts

# Aggressive: also delete CLAUDE.md + settings.json
/path/to/AppBootstrapAI/install.sh /your/repo --uninstall --purge

# Leave settings.local.json MCP entries alone (don't touch your local MCP config)
/path/to/AppBootstrapAI/install.sh /your/repo --uninstall --keep-mcps
```

Classifications:

- **Will delete (unchanged since install)** — current hash matches what we wrote → safe to remove.
- **Locally edited — keep unless `--force-conflicts`** — current hash differs from installed hash. Skipping protects work you did.
- **User-protected — keep unless `--purge`** — `CLAUDE.md` and `.claude/settings.json` are always skipped by default (you almost certainly customized them).
- **MCP entries** — same 3-way safety: removed if `settings.local.json` matches the install-time hash, skipped otherwise unless `--force-conflicts`. Pass `--keep-mcps` to leave them all.

What `--uninstall` always does (regardless of flags):

- Removes the `# --- AppBootstrapAI (...) ---` block from `.gitignore`.
- Deletes the manifest at `.claude/.appbootstrap-manifest.json`.
- Cleans up empty parent directories under `.claude/` only — never touches your project root.
- Preserves every non-`mcpServers` key in `.claude/settings.local.json` (your permissions, custom fields, etc.).

## Saving AI tokens

AI agents pay for every token of context they load. This bundle has a few levers to keep your context bill small without losing functionality. The savings are mostly small individually but compound across long sessions.

### At install time

- **Let auto-detect pick `--platform` for you.** Run `./install.sh .` with no `--platform` flag from inside your project and the installer sniffs the directory: `Package.swift` / `*.xcodeproj` → apple; `build.gradle*` / `gradlew` → android; both present → both; neither → falls back to `both`. The chosen platform + matched signals print in the install header so you can verify. A Swift-only iOS repo lands with just Apple rules in `.claude/rules/`, no Android cruft.
- **Override `--platform` only when detection is wrong.** Auto-detect picks based on what's in the target dir today; an explicit `--platform apple|android|both` always wins. Use this when bootstrapping a fresh empty repo (otherwise the fallback is `both`, which is too broad if you know it's iOS-only).
- **Stick to `--features recommended` (default).** Specialized categories — `persistence` (Core Data), `ai` (Foundation Models), `migration` (XML→Compose), `shrinking` (R8) — only load when you opt in. If your app doesn't use Core Data, the `coredata-swift6-pro` skill is wasted catalog space.
- **Pure-Swift project? Keep `--apple-language swift` (the default).** That skips the two `apple-objc-*` rules. Only switch to `both` if you have genuine `.h`/`.m`/`.mm` files; switch to `objc` for legacy ObjC-only codebases.
- **Not a visionOS app? The default already excludes it.** `--apple-platforms` defaults to `ios,macos,tvos,watchos` — so the visionOS rule (the one sub-platform-specific Apple rule) stays out unless you name `visionos` (or pass `--features …,spatial`). Building for visionOS? `--apple-platforms ios,visionos` pulls it in. Every *other* Apple rule is universal across iOS/macOS/tvOS/watchOS, so there's nothing else to trim per-platform — Apple installs are already lean by design.
- **`--with-mcps` only what you'll use this week.** Each MCP entry adds tool metadata to the agent's catalog. If you're not actively using Firebase MCP, don't install it.

When you over-broaden any of these, `install.sh` prints a "Token-saving tips" block at the end suggesting the tighter flag. That's the install-time feedback loop.

### During development

- **Be specific in prompts.** *"Review `Sources/Networking/Client.swift`"* loads one file. *"Review the codebase"* invites the agent to search the whole tree. The first prompt is usually 10–100x cheaper.
- **Invoke skills by name.** *"Use `swift-concurrency-pro` to review X.swift"* loads that one skill's references. Asking general questions can trigger speculative skill loads — sometimes several at once.
- **Truncate build-log paste-ins.** When a build fails, paste the failing 20–50 lines plus the function signature, not 500 lines of unrelated warnings. (Documented in detail in `apple-objc-best-practices.md` for the mixed-language case; same principle for any language.)
- **One skill at a time.** Running multiple deep-review skills back-to-back in the same turn forces the agent to hold all of their reference docs in context simultaneously. Sequence them across turns.

### Long-running

- **Keep your project's `CLAUDE.md` focused.** It loads on every session. Stale sections and aspirational content are pure context tax — prune ruthlessly.
- **Periodically run `./install.sh --list`** to see what's installed vs. what's available. If you've stopped using a category (e.g., you've fully migrated off XML→Compose), re-run install without it to drop the `migration` rules and `xml-to-compose-migration-pro` skill.
- **Use the MCP server for agent-driven installs.** If you're asking an agent to bootstrap a new repo, the [MCP server](mcp-server/README.md) returns structured JSON (`list_categories`, `list_rules`, `list_skills`) — cheaper for the LLM to consume than parsing the catalog's plain-text format.

### What this won't save

To set expectations honestly: scoping the install down won't dramatically cut your bill if your prompts are already loose. Rules with `globs:` only attach to context when matching files are in the conversation — Android rules in an iOS-only repo are effectively dormant whether or not they're installed. The bigger wins come from prompt discipline and explicit skill invocation, not from install-flag micro-optimization.

## Using with non-Claude AI agents

`install.sh` has a `--agents` flag for picking which agent(s) you want — additive, default `claude`. The bundle generates the right file shape for each agent from the same source `.claude/rules/`.

```bash
# Default — Claude Code only (today's behavior)
/path/to/AppBootstrapAI/install.sh .

# GitHub Copilot — writes .github/copilot-instructions.md (concat of in-scope rules)
/path/to/AppBootstrapAI/install.sh . --agents copilot

# Cursor — writes per-rule .cursor/rules/<name>.mdc files
/path/to/AppBootstrapAI/install.sh . --agents cursor

# Amazon Kiro — writes per-rule .kiro/steering/<name>.md files
/path/to/AppBootstrapAI/install.sh . --agents kiro

# Mixed team — install for Claude + Copilot + Cursor in one go
/path/to/AppBootstrapAI/install.sh . --agents claude,copilot,cursor

# Everything — claude + copilot + cursor + gemini + codex + kiro
/path/to/AppBootstrapAI/install.sh . --agents all
```

Per-agent file shape:

| Agent  | Token     | File(s) written                       | Format                       |
|--------|-----------|---------------------------------------|------------------------------|
| Claude Code  | `claude`  | `.claude/rules/`, `.claude/skills/`, `.claude/settings.json`, `CLAUDE.md` | Native — per-rule files + skill directories |
| GitHub Copilot | `copilot` | `.github/copilot-instructions.md` | One concatenated markdown file with all in-scope rules |
| Cursor | `cursor`  | `.cursor/rules/<name>.mdc`             | Per-rule files (1:1 with `.claude/rules/*.md`, just renamed) |
| Gemini CLI | `gemini`  | `GEMINI.md`                         | One concatenated markdown file |
| Codex CLI / `AGENTS.md`-aware tools | `codex`   | `AGENTS.md`                          | One concatenated markdown file |
| Amazon Kiro | `kiro`    | `.kiro/steering/<name>.md`           | Per-rule [steering files](https://kiro.dev/docs/steering/); each rule's `globs` becomes `inclusion: fileMatch` + `fileMatchPattern`, so a rule loads only when a matching file is open |

**How it works:**

- **Same source, multiple targets.** Every agent gets content derived from the same `.claude/rules/*.md` source-of-truth (gated by `--platform` / `--apple-language` / `--features`). Output is deterministic — concat agents (Copilot/Gemini/Codex) and per-rule agents (Cursor `.mdc`, Kiro steering with its rewritten `inclusion`/`fileMatchPattern` frontmatter) all produce the same bytes given the same inputs — so `--upgrade` can diff cleanly.
- **Skills are Claude-only.** Skills are procedural sub-agents that only run inside Claude Code. Non-Claude agents get rules only. If you want a skill's checklist in another agent's context, copy it into the relevant rule manually.
- **Existing files are never overwritten on install.** If you already have `.github/copilot-instructions.md` or `GEMINI.md`, install skips and prints a notice. `--upgrade` does the 3-way diff like any other tracked file.
- **`--upgrade --apply` opts in / out of agents.** Pass `--agents` on the command line to opt into a new agent (its files show up as additions). Pass `--agents <fewer>` + `--prune` to drop an agent (its files appear as orphans and get deleted).
- **The manifest tracks per-agent.** `selection.agents_input` / `selection.agents_resolved` and per-file `type: agent-file-<name>` entries so the upgrade flow knows which files came from which agent.

### Alternative: external sync tools

If you'd rather keep a single source-of-truth and let another tool fan out to a wider set of agents (Cline, Goose, Roo, Windsurf, Amp, Antigravity, Factory Droid, etc.), point one of these at `.claude/`:

| Tool | Approach |
|------|----------|
| **[`ruler`](https://github.com/intellectronica/ruler)** | Reads from a unified source (you can point it at `.claude/rules/`) and applies the same rules to every supported agent's expected path on `ruler apply`. Maintains the per-tool path matrix for you. |
| **[`block/ai-rules`](https://github.com/block/ai-rules)** | Manages rules, commands, and skills across Claude, Cline, Codex, Copilot, Cursor, Firebender, Gemini, Goose, Kilocode, Roo. Installs via `curl` to `~/.local/bin/ai-rules`. |
| **[`lbb00/ai-rules-sync`](https://github.com/lbb00/ai-rules-sync)** | npm-installable CLI; similar fan-out model. |

Use a sync tool when you need agents that `install.sh --agents` doesn't cover, or when you want a single watch-and-rebuild loop instead of explicit `--upgrade --apply` runs.

## Repo layout

```
.
├── .claude/
│   ├── rules/
│   │   ├── android-accessibility-best-practices.md    # Android a11y
│   │   ├── android-ai-best-practices.md               # Gemini Nano / Firebase AI Logic (ai)
│   │   ├── android-compose-best-practices.md          # Jetpack Compose patterns
│   │   ├── android-coroutines-best-practices.md       # Structured concurrency
│   │   ├── android-documentation-strategy.md          # KDoc strategy + Dokka
│   │   ├── android-gradle-conventions.md              # Gradle DSL, version catalogs, modules
│   │   ├── android-linting-strategy.md                # ktlint + detekt + Android Lint (linting)
│   │   ├── android-localization-best-practices.md     # strings.xml, plurals, RTL
│   │   ├── android-logging-strategy.md                # Timber, level discipline, release-stripping (logging)
│   │   ├── android-play-beta-deployment.md            # Play beta tracks, signing, CI (deployment)
│   │   ├── android-project-rules.md                   # Kotlin/Compose/MVVM/Hilt
│   │   ├── android-testing-strategy.md                # Android test strategy + JaCoCo
│   │   ├── apple-accessibility-best-practices.md      # SwiftUI a11y
│   │   ├── apple-documentation-strategy.md            # DocC strategy + deprecation
│   │   ├── apple-foundation-models.md                 # On-device LLM patterns
│   │   ├── apple-linting-strategy.md                  # SwiftLint + formatter (linting)
│   │   ├── apple-localization-best-practices.md       # String Catalogs, plurals, RTL
│   │   ├── apple-logging-strategy.md                  # os.Logger, privacy markers, levels (logging)
│   │   ├── apple-modular-architecture.md              # Thin app shell + fat local SPM package
│   │   ├── apple-objc-accessibility-best-practices.md # UIKit a11y in ObjC
│   │   ├── apple-objc-best-practices.md               # Modern Objective-C
│   │   ├── apple-spm-package-conventions.md           # Package.swift authoring
│   │   ├── apple-swift6-strict-concurrency.md         # Swift 6.4 strict concurrency (Xcode 27)
│   │   ├── apple-swiftui-mvvm.md                      # SwiftUI MVVM conventions
│   │   ├── apple-testflight-deployment.md             # TestFlight, ASC API, signing, CI (deployment)
│   │   ├── apple-testing-strategy.md                  # Apple test strategy + coverage
│   │   ├── apple-visionos-best-practices.md           # visionOS / RealityKit / spatial UX (spatial)
│   │   ├── concise-comments-and-commits.md            # terse comments + commit messages (core)
│   │   └── project-documentation.md                   # README/CHANGELOG/ADR/inline comments
│   ├── skills/                        # On-demand skills
│   │   ├── android-accessibility-pro/          # TalkBack / keyboard / contrast audit (ui)
│   │   ├── android-compose-pro/                # Compose stability / effects / lazy perf (ui)
│   │   ├── android-coroutines-pro/             # Coroutines & Flow correctness (concurrency)
│   │   ├── android-gradle-architecture-pro/    # NiA-style conventions + version catalogs
│   │   ├── coredata-swift6-pro/
│   │   ├── r8-shrink-pro/                      # ProGuard/R8 rules
│   │   ├── swift-concurrency-pro/
│   │   ├── swift-docc-pro/
│   │   ├── swift-error-handling-pro/
│   │   ├── swift-logging-pro/
│   │   ├── swift-package-pro/
│   │   ├── swift-testing-pro/
│   │   ├── swift-accessibility-pro/            # VoiceOver / keyboard / contrast audit (ui)
│   │   ├── swiftdata-pro/                      # SwiftData review (persistence)
│   │   ├── swiftui-pro/
│   │   └── xml-to-compose-migration-pro/       # XML/Fragment → Compose migration
│   └── settings.json                  # Baseline permissions
├── templates/
│   ├── CLAUDE.template.apple.md       # Starter for Apple-only projects
│   ├── CLAUDE.template.android.md     # Starter for Android-only projects
│   ├── CLAUDE.template.md             # Starter for cross-platform projects
│   └── Package.template.swift         # Starter Package.swift with makeTargets() helper
├── scripts/                           # Standalone repo tools (run from the bundle, not installed)
│   └── scaffold-spm-package.sh        # Generate a KozBon-style local SPM package skeleton
├── mcp-recipes/                       # Recipes for --with-mcps (one JSON per supported MCP)
│   ├── xcodebuildmcp.json             # Apple
│   ├── xcode-native.json              # Apple (Xcode 26.3+ first-party)
│   ├── android-mcp-server.json        # Android
│   ├── firebase.json                  # Cross-platform (official Google MCP)
│   └── sentry.json                    # Cross-platform (official hosted Sentry MCP)
├── mcp-server/                        # MCP server wrapping install.sh as typed tools
│   ├── src/index.ts                   # 9 tools: recommend_setup, list_*, preview_install, install, preview/uninstall
│   ├── package.json
│   └── README.md                      # MCP setup instructions for Claude Code / Cursor / others
├── install.sh                         # CLI dispatcher (~450 lines): args, validation, mode dispatch
├── lib/                               # install.sh's sourced modules (keeps the entry point small)
│   ├── help.txt                       # Full --help text (cat'd by the -h/--help handler)
│   ├── predicates.sh                  # file_category, should_install_*, sha256, concat helpers
│   ├── detect_platform.sh             # --platform auto-detection from target-dir signals
│   ├── list_modes.sh                  # --list and --list-mcps handlers
│   ├── install_mode.sh                # the install path (skills, rules, agents, gitignore, manifest)
│   ├── install_mcps.sh                # --with-mcps merge wrapper (calls mcp_merge.py)
│   ├── upgrade_mode.sh                # --upgrade bash wrapper (calls upgrade.py)
│   ├── upgrade.py                     # Python: upgrade plan/apply executor (3-way diff)
│   ├── uninstall.py                   # Python: --uninstall executor
│   ├── mcp_merge.py                   # Python: MCP merge into settings.local.json
│   ├── inherit_selection.py           # Python: read selection fields from a manifest
│   └── recommend.py                   # Python: `recommend` — analyze a dir → suggested command
├── AGENTS.md                          # How an AI agent should operate this package (recommend → preview → run)
├── RENAMES.md                         # Rule/skill rename map honored by --upgrade
├── CHANGELOG.md                       # Keep-a-Changelog notable changes
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

- **Skills exist for both Apple and Android.** Apple has 9 skills (concurrency, testing, SwiftUI, Core Data, SwiftData, DocC, error handling, logging, SPM); Android has 5 (Compose, coroutines/Flow, Gradle architecture, XML-to-Compose migration, R8/ProGuard) — the Compose-pro and coroutines-pro roadmap items shipped.
- All rules (Apple + Android) are loaded automatically by `globs` and apply equally; there is no "primary" / "secondary" platform in the bundle's design.

## Changelog

Notable changes are tracked in [`CHANGELOG.md`](CHANGELOG.md), following the [Keep a Changelog](https://keepachangelog.com) format the bundle's own `project-documentation.md` rule recommends.

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
